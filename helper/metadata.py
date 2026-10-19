# SPDX-License-Identifier: GPL-2.0-only
# Copyright and licensing scope: see COPYRIGHT.md in the project root.
"""Read full Video Metadata Pro value lists without changing media files."""
import json
import re
import subprocess
import struct
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import unquote, urlsplit

FIELDS = ('artist', 'album', 'genre')


def normalize(data):
    """Split whitespace-delimited tags and keep an item's genres out of albums."""
    values = {
        field: list(dict.fromkeys(part for value in data[field] for part in value.split()))
        for field in FIELDS
    }
    genres = {value.casefold() for value in values['genre']}
    values['album'] = [value for value in values['album'] if value.casefold() not in genres]
    return values


def unpack(values, record):
    try:
        decoded = json.loads(record)
        if (isinstance(decoded, list) and decoded
                and all(isinstance(v, str) and v for v in decoded)
                and values == [' '.join(decoded)]):
            return decoded
    except (TypeError, ValueError, UnicodeError):
        pass
    return values


def local_path(uri):
    if uri.startswith('/'):
        return Path(uri)
    parsed = urlsplit(uri)
    if parsed.scheme == 'file' and parsed.netloc in ('', 'localhost'):
        return Path(unquote(parsed.path))
    return None


def command(*args):
    result = subprocess.run(args, capture_output=True, timeout=30)
    if result.returncode not in (0, 1):
        raise ValueError(result.stderr.decode('utf-8', 'replace').strip() or 'Metadata reader failed')
    return result.stdout


def read_mp4(path):
    from mutagen.mp4 import MP4
    media = MP4(path)
    tags = media.tags or {}
    data = {'duration': mp4_duration(path), 'title': (tags.get('\xa9nam') or [''])[0]}
    for field, atom in {'artist': '\xa9ART', 'album': '\xa9alb', 'genre': '\xa9gen'}.items():
        values = list(dict.fromkeys(tags.get(atom, [])))
        record = tags.get('----:org.video-metadata-pro:display-' + field + '-values', [None])[0]
        data[field] = unpack(values, record)
    data['album'] = unpack(data['album'], tags.get('----:org.video-metadata-pro:album-values', [None])[0])
    data.update(normalize(data))
    return data


def mp4_duration(path):
    """Read the movie header, including video-only files (Mutagen times audio)."""
    with path.open('rb') as stream:
        def atoms(start, end):
            offset = start
            while offset + 8 <= end:
                stream.seek(offset)
                size, name = struct.unpack('>I4s', stream.read(8))
                header = 8
                if size == 1:
                    size = struct.unpack('>Q', stream.read(8))[0]
                    header = 16
                elif size == 0:
                    size = end - offset
                if size < header or offset + size > end:
                    raise ValueError('Invalid MP4 atom size')
                yield name, offset + header, offset + size
                offset += size
        for name, start, end in atoms(0, path.stat().st_size):
            if name != b'moov':
                continue
            for child, body, limit in atoms(start, end):
                if child != b'mvhd':
                    continue
                stream.seek(body)
                data = stream.read(min(32, limit - body))
                if not data or data[0] not in (0, 1):
                    return -1
                offset, fmt = (12, '>II') if data[0] == 0 else (20, '>IQ')
                scale, ticks = struct.unpack_from(fmt, data, offset)
                unknown = (1 << (32 if data[0] == 0 else 64)) - 1
                return ticks / scale if scale and 0 < ticks < unknown else -1
    return -1


def mkv_values(root):
    data = {field: [] for field in FIELDS}
    records = {'album': [], 'genre': []}
    for tag in root.findall('Tag'):
        targets = tag.find('Targets')
        if targets is not None and any(t.tag.endswith('UID') for t in targets):
            continue
        level = tag.findtext('Targets/TargetTypeValue', '50')
        for node in tag.findall('Simple'):
            name, value = node.findtext('Name'), node.findtext('String')
            if name == 'VIDEO_METADATA_PRO_ALBUM_VALUES':
                records['album'].append(value)
            elif name == 'VIDEO_METADATA_PRO_GENRE_VALUES':
                records['genre'].append(value)
            if (not value or node.findtext('TagLanguage', 'und') != 'und'
                    or node.findtext('TagLanguageIETF', 'und') != 'und'
                    or node.findtext('DefaultLanguage', '1') != '1'):
                continue
            field = None
            if name == 'ARTIST' and level != '50':
                field = 'artist'
            elif name == 'ALBUM' or (name == 'TITLE' and level == '50'):
                field = 'album'
            elif name == 'GENRE':
                field = 'genre'
            if field and value not in data[field]:
                data[field].append(value)
    for field, field_records in records.items():
        for record in field_records:
            data[field] = unpack(data[field], record)
    return normalize(data)


def read_mkv(path):
    xml = command('mkvextract', str(path), 'tags')
    data = mkv_values(ET.fromstring(xml)) if xml.strip() else {k: [] for k in FIELDS}
    # mkvinfo works in the existing Snap runtime; mkvmerge additionally needs
    # codec libraries that the editor's read/write-only runtime does not ship.
    info = command('mkvinfo', '--ui-language', 'en_US', '--output-charset', 'UTF-8', str(path))
    data.update(mkv_info(info.decode('utf-8')))
    return data


def mkv_info(text):
    result = {'title': '', 'duration': -1}
    in_segment_info = False
    for line in text.splitlines():
        if line.startswith('|+'):
            in_segment_info = line == '|+ Segment information'
        if not in_segment_info:
            continue
        if line.startswith('| + Title: '):
            result['title'] = line[len('| + Title: '):]
        match = re.fullmatch(r'\| \+ Duration: (\d+):(\d{2}):(\d{2}(?:\.\d+)?)', line)
        if match:
            hours, minutes, seconds = match.groups()
            result['duration'] = int(hours) * 3600 + int(minutes) * 60 + float(seconds)
    return result


def read(path):
    suffix = path.suffix.lower()
    if suffix in ('.mp4', '.m4v', '.m4a'):
        return read_mp4(path)
    if suffix in ('.mkv', '.mka', '.webm'):
        return read_mkv(path)
    return None
