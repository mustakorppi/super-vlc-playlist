# SPDX-License-Identifier: GPL-2.0-only
# Copyright and licensing scope: see COPYRIGHT.md in the project root.
"""Persistent plugin settings, separate from installed code and metadata cache."""
import json
import os
from pathlib import Path
import tempfile


def load(support, home):
    path = support / 'settings.json'
    try:
        data = json.loads(path.read_text(encoding='utf-8'))
    except FileNotFoundError:
        return {'version': 1, 'preset_directory': str(home / 'Super Playlist Presets'),
                'export_directory': str(support / 'exports')}
    if not isinstance(data, dict) or data.get('version') != 1:
        raise ValueError('Unsupported settings format.')
    directory = data.get('preset_directory')
    if not isinstance(directory, str) or not Path(directory).is_absolute():
        raise ValueError('Invalid preset directory in settings.')
    data.setdefault('export_directory', str(support / 'exports'))
    if not isinstance(data['export_directory'], str) or not Path(data['export_directory']).is_absolute():
        raise ValueError('Invalid export directory in settings.')
    return data


def save(support, home, directory, key='preset_directory'):
    if key not in ('preset_directory', 'export_directory'):
        raise ValueError('Unknown folder setting.')
    if not directory or not directory.strip():
        raise ValueError('Enter a folder.')
    if directory == '~' or directory.startswith('~/'):
        directory = str(home) + directory[1:]
    path = Path(directory)
    if not path.is_absolute():
        raise ValueError('Use an absolute folder path or ~/folder.')
    path = path.resolve()
    path.mkdir(parents=True, exist_ok=True)
    # Exercise actual access in the helper runtime, including Snap confinement.
    with os.scandir(path) as entries:
        next(entries, None)
    with tempfile.TemporaryFile(dir=path) as probe:
        probe.write(b'preset folder access check')
        probe.flush()
    data = load(support, home)
    data[key] = str(path)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=support,
                                         prefix='settings-', suffix='.tmp', delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(data, stream, ensure_ascii=False, indent=2)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, support / 'settings.json')
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return data
