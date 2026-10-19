# SPDX-License-Identifier: GPL-2.0-only
# Copyright and licensing scope: see COPYRIGHT.md in the project root.
"""Named M3U8 exports, published only after a complete successful write."""
import os
from pathlib import Path
import tempfile

from . import presets, settings


def save(support, home, name, items):
    if name.lower().endswith('.m3u8'):
        name = name[:-5]
    try:
        presets.valid_name(name)
    except ValueError as error:
        raise ValueError(str(error).replace('preset name', 'playlist name')) from None
    if not items:
        raise ValueError('No matches to export.')
    content = ['#EXTM3U\n']
    for item in items:
        if any(c in item['uri'] for c in '\r\n\x00'):
            raise ValueError('Cannot export a URI containing a newline or NUL.')
        title = item['title'].replace('\r', ' ').replace('\n', ' ')
        content.append(f"#EXTINF:{int(item['duration'])},{title}\n{item['uri']}\n")
    folder = Path(settings.load(support, home)['export_directory'])
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / (name + '.m3u8')
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=folder,
                                         prefix='.export-', suffix='.tmp', delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(''.join(content))
            stream.flush()
            os.fsync(stream.fileno())
        try:
            os.link(temporary, path)
        except FileExistsError:
            raise ValueError('A playlist with that name already exists. Choose another name.') from None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return path
