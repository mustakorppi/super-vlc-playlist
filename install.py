#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# Copyright and licensing scope: see COPYRIGHT.md in the project root.
"""Install Super Playlist for conventional Linux VLC 3 or the existing VLC Snap runtime."""
import argparse
from datetime import date
import json
import re
import os
from pathlib import Path
import shutil
import sys


def lua_string(value):
    return '"' + ''.join('\\%03d' % byte for byte in str(value).encode('utf-8')) + '"'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data-dir', type=Path)
    parser.add_argument('--python', default=sys.executable,
                        help='Python interpreter or launcher visible to VLC')
    parser.add_argument('--snap', action='store_true',
                        help='Reuse the runtime installed by Video Metadata Pro for Snap VLC')
    args = parser.parse_args()
    interpreter = args.python
    if args.snap:
        if args.data_dir:
            parser.error('--snap and --data-dir cannot be combined')
        runtime = Path.home() / 'snap/vlc/common/video-metadata-runtime'
        launcher = runtime / 'python-launcher'
        required = [launcher, runtime / 'python/mutagen/__init__.py']
        required += [runtime / 'mkvtoolnix/usr/bin' / tool for tool in ('mkvextract', 'mkvinfo')]
        if not all(path.is_file() for path in required):
            parser.error('Install Video Metadata Pro for Snap first; its existing runtime is required.')
        if not (Path.home() / 'snap/vlc/current').is_dir():
            parser.error('Launch Snap VLC once before installing.')
        data_dir = Path.home() / 'snap/vlc/current/.local/share/vlc'
        interpreter = str(launcher)
    else:
        data_dir = args.data_dir or Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'vlc'
    root = Path(__file__).resolve().parent
    try:
        release = json.loads((root / 'release.json').read_text(encoding='utf-8'))
        version, build_date = release['version'], release['build_date']
        if not isinstance(version, str) or not re.fullmatch(r'[0-9]+(?:\.[0-9]+){1,2}(?: RC[1-9][0-9]*)?', version):
            raise ValueError('version must contain two or three numeric components, optionally followed by RC1, RC2, etc.')
        if not isinstance(build_date, str) or date.fromisoformat(build_date).isoformat() != build_date:
            raise ValueError('build_date must use YYYY-MM-DD')
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.error(f'Invalid release.json: {error}')
    destination = data_dir.expanduser().absolute() / 'lua/extensions'
    support = destination / 'super_playlist_support'
    for folder in ('helper', 'jobs', 'exports'):
        (support / folder).mkdir(parents=True, exist_ok=True, mode=0o700)
    for path in (root / 'helper').glob('*.py'):
        shutil.copy2(path, support / 'helper' / path.name)
    shutil.copy2(root / 'run_worker.py', support / 'run_worker.py')
    for name in ('LICENSE', 'COPYRIGHT.md', 'release.json'):
        shutil.copy2(root / name, support / name)
    config = ('local SUPPORT_DIR = ' + lua_string(support) + '\nlocal PYTHON = ' + lua_string(interpreter)
              + '\nlocal USER_HOME = ' + lua_string(Path.home())
              + '\nlocal VERSION = ' + lua_string(version)
              + '\nlocal BUILD_DATE = ' + lua_string(build_date))
    extension = (root / 'vlc/super_playlist.lua').read_text(encoding='utf-8').replace('-- @CONFIG@', config)
    target = destination / 'super_playlist.lua'
    target.write_text(extension, encoding='utf-8')
    print('Installed:', target)
    print('Restart VLC, then select View > Super Playlist.')


if __name__ == '__main__':
    main()
