# SPDX-License-Identifier: GPL-2.0-only
# Copyright and licensing scope: see COPYRIGHT.md in the project root.
"""Named, versioned filter presets. Files contain data, never executable code."""
import json
import os
from pathlib import Path
import tempfile

from . import settings

FIELDS = ('artist', 'album', 'genre')


class PresetExists(ValueError):
    pass


def valid_name(name):
    if (not isinstance(name, str) or not name.strip() or name != name.strip()
            or name in ('.', '..') or any(c in name for c in '/\\')
            or any(ord(c) < 32 or ord(c) == 127 for c in name)
            or len(name.encode('utf-8')) > 180):
        raise ValueError('Use a preset name of 1–180 UTF-8 bytes, without path separators, '
                         'control characters, or leading/trailing spaces.')
    return name


def validate(data):
    from .worker import duration_ranges
    if not isinstance(data, dict) or type(data.get('version')) is not int or data['version'] != 1:
        raise ValueError('Unsupported preset format or version.')
    valid_name(data.get('name'))
    state = data.get('filters')
    if not isinstance(state, dict):
        raise ValueError('Invalid preset filters.')
    def strings(value):
        return isinstance(value, list) and all(isinstance(v, str) and '\x00' not in v for v in value)
    if (not strings(state.get('patterns'))
            or not isinstance(state.get('title_input'), str)
            or '\x00' in state['title_input']
            or not isinstance(state.get('ranges'), str)
            or type(state.get('unknown')) is not bool
            or not strings(state.get('all')) or not set(state['all']) <= set(FIELDS)
            or not isinstance(state.get('selected'), dict)
            or set(state['selected']) != set(FIELDS)
            or not all(strings(state['selected'][key]) for key in FIELDS)):
        raise ValueError('Invalid preset filter values.')
    duration_ranges(state['ranges'])
    return data


def directory(support, home):
    return Path(settings.load(support, home)['preset_directory'])


def names(folder):
    try:
        entries = list(folder.iterdir())
    except FileNotFoundError:
        return []
    result = []
    for entry in entries:
        if entry.suffix != '.json' or entry.is_symlink() or not entry.is_file():
            continue
        try:
            result.append(valid_name(entry.stem))
        except ValueError:
            continue
    return sorted(result, key=lambda name: (name.casefold(), name))


def load(folder, name):
    path = folder / (valid_name(name) + '.json')
    if path.is_symlink():
        raise ValueError('Preset must be a regular file, not a symbolic link.')
    with path.open('rb') as stream:
        content = stream.read(1024 * 1024 + 1)
    if len(content) > 1024 * 1024:
        raise ValueError('Preset is too large (maximum 1 MiB).')
    data = validate(json.loads(content.decode('utf-8')))
    # The filename is the library name, allowing users to rename files directly.
    data['name'] = name
    return data


def save(folder, name, state, replace=False):
    data = validate({'version': 1, 'name': valid_name(name), 'filters': state})
    content = json.dumps(data, ensure_ascii=False, indent=2) + '\n'
    if len(content.encode('utf-8')) > 1024 * 1024:
        raise ValueError('Preset is too large (maximum 1 MiB).')
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / (name + '.json')
    if path.is_symlink():
        raise ValueError('Preset must be a regular file, not a symbolic link.')
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=folder,
                                         prefix='.preset-', suffix='.tmp', delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        if replace:
            os.replace(temporary, path)
        else:
            try:
                os.link(temporary, path)
            except FileExistsError:
                raise PresetExists('Preset already exists.') from None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return data


def state_rows(state):
    yield ['E', state['title_input']]
    for pattern in state['patterns']:
        yield ['T', pattern]
    yield ['D', state['ranges']]
    if state['unknown']:
        yield ['U']
    for key in FIELDS:
        for value in state['selected'][key]:
            yield ['F', key, value]
        if key in state['all']:
            yield ['A', key]
