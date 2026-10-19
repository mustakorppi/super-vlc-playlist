# SPDX-License-Identifier: GPL-2.0-only
# Copyright and licensing scope: see COPYRIGHT.md in the project root.
"""One background job. Percent-encoded TSV is data, never executable Lua."""
import json
import math
import os
import re
import sys
import tempfile
from pathlib import Path
from urllib.parse import quote, unquote

from . import metadata, settings, presets, exports

FIELDS = metadata.FIELDS
CACHE_VERSION = 3


def wire(row):
    return '\t'.join(quote(str(v), safe='') for v in row) + '\n'


def rows(path):
    return [[unquote(v) for v in line.rstrip('\n').split('\t')]
            for line in path.read_text(encoding='utf-8').splitlines() if line]


def atomic(path, text):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(text, encoding='utf-8')
    temporary.replace(path)


def parse_request(data):
    items, by_id = [], {}
    options = {'patterns': [], 'selected': {k: [] for k in FIELDS}, 'all': set(), 'ranges': ''}
    for row in data:
        kind = row[0]
        if kind == 'I':
            _, identity, uri, title, duration = row
            item = dict(id=identity, uri=uri, title=title, duration=float(duration),
                        **{key: [] for key in FIELDS})
            if identity in by_id:
                raise ValueError('Duplicate playlist ID')
            items.append(item)
            by_id[identity] = item
        elif kind == 'V':
            _, identity, key, value = row
            if key not in FIELDS:
                raise ValueError('Unknown metadata field')
            by_id[identity][key].append(value)
        elif kind == 'F':
            options['selected'][row[1]].append(row[2])
        elif kind == 'A':
            options['all'].add(row[1])
        elif kind == 'T':
            options['patterns'].append(row[1])
        elif kind == 'D':
            options['ranges'] = row[1]
        elif kind == 'U':
            options['unknown'] = True
        elif kind == 'M':
            options['mode'] = row[1]
        elif kind == 'H':
            options['home'] = row[1]
        elif kind == 'P':
            options['preset_directory'] = row[1]
        elif kind == 'X':
            options['export_directory'] = row[1]
        elif kind == 'E':
            options['title_input'] = row[1]
        elif kind == 'N':
            options['name'] = row[1]
        elif kind == 'R':
            options['replace'] = True
        else:
            raise ValueError('Unknown request record')
    return items, options


def item_rows(items):
    for item in items:
        yield ['I', item['id'], item['uri'], item['title'], item['duration']]
        for key in FIELDS:
            for value in item[key]:
                yield ['V', item['id'], key, value]


def seconds(text):
    text = text.strip()
    if not re.fullmatch(r'\d+(?::[0-5]\d){0,2}', text):
        raise ValueError('Duration must be seconds, mm:ss or hh:mm:ss (seconds/minutes below 60).')
    value = 0
    for part in text.split(':'):
        value = value * 60 + int(part)
    return value


def duration_ranges(text):
    if not text.strip():
        return []
    result = []
    for part in text.split(';'):
        if part.count('-') != 1:
            raise ValueError('Use duration ranges such as 03:00-08:00; 12:00-.')
        left, right = part.split('-')
        if not left.strip() and not right.strip():
            raise ValueError('Each duration range needs at least one bound.')
        minimum = seconds(left) if left.strip() else 0
        maximum = seconds(right) if right.strip() else math.inf
        if minimum > maximum:
            raise ValueError('Minimum duration exceeds maximum duration.')
        result.append((minimum, maximum))
    return result


def title_match(title, pattern):
    title, pattern = title.casefold(), pattern.strip().casefold()
    if '*' not in pattern and '?' not in pattern:
        return pattern in title
    expression = ''.join('.*' if c == '*' else '.' if c == '?' else re.escape(c) for c in pattern)
    return re.fullmatch(expression, title, re.DOTALL) is not None


def filter_items(items, options):
    ranges = duration_ranges(options['ranges'])
    patterns = [p for p in options['patterns'] + [options.get('title_input', '')] if p.strip()]
    selected = {k: {v.casefold() for v in options['selected'][k]} for k in FIELDS}
    result = []
    for item in items:
        item.update(metadata.normalize(item))
        if patterns and not any(title_match(item['title'], p) for p in patterns):
            continue
        matched = True
        for key, wanted in selected.items():
            values = {v.casefold() for v in item[key]} or {''}
            if wanted and not (wanted <= values if key in options['all'] else bool(wanted & values)):
                matched = False
                break
        if not matched:
            continue
        duration = item['duration']
        if ranges:
            if not math.isfinite(duration) or duration < 0:
                if not options.get('unknown'):
                    continue
            elif not any(low <= duration <= high for low, high in ranges):
                continue
        result.append(item)
    return result


def scan(items, job):
    cache_path = job.parent.parent / 'cache.json'
    try:
        cache = json.loads(cache_path.read_text(encoding='utf-8'))
        if not isinstance(cache, dict):
            cache = {}
    except (OSError, ValueError):
        cache = {}
    updated, warnings = {}, []
    for index, item in enumerate(items, 1):
        item.update(metadata.normalize(item))
        if (job / 'cancel').exists():
            raise ValueError('Scan cancelled.')
        atomic(job / 'progress.txt', 'Reading %d / %d' % (index, len(items)))
        path = metadata.local_path(item['uri'])
        if path is None:
            continue
        try:
            stat = path.stat()
            key = str(path)
            stamp = [stat.st_size, stat.st_mtime_ns]
            entry = cache.get(key, {})
            data = (entry.get('data') if entry.get('stamp') == stamp
                    and entry.get('reader_version') == CACHE_VERSION else metadata.read(path))
            if data is not None:
                updated[key] = {'stamp': stamp, 'reader_version': CACHE_VERSION, 'data': data}
                item.update({k: data[k] for k in FIELDS})
                item.update(metadata.normalize(item))
                if data.get('title'):
                    item['title'] = data['title']
                if data.get('duration', -1) >= 0:
                    item['duration'] = data['duration']
        except Exception as error:
            warnings.append('%s: %s' % (path.name, error))
    # Independent temporary files prevent concurrent extension jobs colliding.
    with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=cache_path.parent,
                                     prefix='cache-', delete=False) as stream:
        json.dump(updated, stream, ensure_ascii=False)
        temporary = stream.name
    os.replace(temporary, cache_path)
    return items, warnings


def execute(job):
    try:
        items, options = parse_request(rows(job / 'request.txt'))
        warnings = []
        if options.get('mode') in ('settings_load', 'settings_save'):
            home = Path(options['home'])
            if options['mode'] == 'settings_save':
                key = 'export_directory' if 'export_directory' in options else 'preset_directory'
                data = settings.save(job.parent.parent, home, options[key], key)
            else:
                data = settings.load(job.parent.parent, home)
            output = [['P', data['preset_directory']], ['X', data['export_directory']]]
            if options['mode'] == 'settings_save':
                output += [['N', name] for name in presets.names(Path(data['preset_directory']))]
            atomic(job / 'result.txt', ''.join(wire(row) for row in output + [['OK', 0]]))
            return
        elif options.get('mode') in ('preset_list', 'preset_load', 'preset_save'):
            folder = presets.directory(job.parent.parent, Path(options['home']))
            output = []
            if options['mode'] == 'preset_load':
                data = presets.load(folder, options['name'])
                output = [['L', data['name']]] + list(presets.state_rows(data['filters']))
            elif options['mode'] == 'preset_save':
                state = {key: options[key] for key in ('patterns', 'selected', 'ranges')}
                state.update(title_input=options.get('title_input', ''),
                             unknown=options.get('unknown', False), all=sorted(options['all']))
                data = presets.save(folder, options['name'], state, options.get('replace', False))
                output = [['S', data['name']]]
            output += [['N', name] for name in presets.names(folder)]
            atomic(job / 'result.txt', ''.join(wire(row) for row in output + [['OK', 0]]))
            return
        elif options.get('mode') == 'export':
            path = exports.save(job.parent.parent, Path(options['home']), options['name'], items)
            atomic(job / 'result.txt', wire(['X', path]) + wire(['OK', len(items)]))
            return
        elif options.get('mode') == 'scan':
            items, warnings = scan(items, job)
        elif options.get('mode') == 'filter':
            items = filter_items(items, options)
        else:
            raise ValueError('Unknown job mode')
        output = list(item_rows(items)) + [['W', value] for value in warnings]
        output.append(['OK', len(items)])
    except presets.PresetExists:
        output = [['EXISTS', options['name']], ['OK', 0]]
    except Exception as error:
        output = [['ERROR', str(error)]]
    atomic(job / 'result.txt', ''.join(wire(row) for row in output))


if __name__ == '__main__':
    execute(Path(sys.argv[1]))
