#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Lossless XPM -> RGBA PNG conversion. Python standard library only.
Original art: Copyright (C) 1989-2007 Electronic Arts Inc.; see bundled README.
No network, resizing, palette substitution or third-party assets.
"""
import ast
import hashlib
import json
from pathlib import Path
import re
import struct
import sys
import zlib

ROOT = Path(__file__).resolve().parents[1] / 'Resources' / 'OriginalGraphics'
COMMIT = 'c98f6b08519887b450d9be198bfca5237aab6d0c'
SOURCES = {
    'tiles.xpm': ('images/tiles.xpm', '5a2432b42112aa1e904c736e362f75bc902e8c60adf69f4c965995f869ef6cbb'),
    'UPSTREAM-README.txt': ('README', '1d2b942bf5f657b85c07385f90049fa5caf3345cdeed2d49e59ce34dc8625d39'),
    'UPSTREAM-COPYING.txt': ('COPYING', '8ceb4b9ee5adedde47b31e975c1d90c73ad27b6b165a1dcd80c7c545eb65b903'),
}


def pixels():
    strings = [ast.literal_eval(re.match(r'"(?:[^"\\]|\\.)*"', line)[0])
               for line in (ROOT / 'tiles.xpm').read_text().splitlines() if line.startswith('"')]
    width, height, count, cpp = map(int, strings[0].split())
    assert (width, height, count, cpp) == (16, 15360, 14, 1)
    palette = {}
    for entry in strings[1:1 + count]:
        colour = re.search(r'\bc\s+(#[0-9A-Fa-f]{12})$', entry[cpp:])[1][1:]
        # Each upstream 16-bit channel repeats an 8-bit value; exact conversion.
        channels = [int(colour[i:i + 4], 16) for i in (0, 4, 8)]
        assert all(c % 257 == 0 for c in channels)
        palette[entry[:cpp]] = bytes([c // 257 for c in channels] + [255])
    rows = strings[1 + count:]
    assert len(rows) == height and all(len(r) == width * cpp for r in rows)
    return width, height, b''.join(palette[c] for row in rows for c in row)


def png(width, height, rgba):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    stride = width * 4
    scanlines = b''.join(b'\0' + rgba[y * stride:(y + 1) * stride] for y in range(height))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(scanlines, 9)) + chunk(b'IEND', b''))


def main():
    assets = []
    for name, (source, expected) in SOURCES.items():
        data = (ROOT / name).read_bytes()
        assert hashlib.sha256(data).hexdigest() == expected, name
        blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        assets.append(dict(file=name, sourcePath='micropolis-activity/' + source,
                           url=f'https://raw.githubusercontent.com/SimHacker/micropolis/{COMMIT}/micropolis-activity/{source}',
                           sha256=expected, gitBlob=blob))
    width, height, rgba = pixels()
    image = png(width, height, rgba)
    provenance = dict(repository='https://github.com/SimHacker/micropolis', commit=COMMIT,
                      license='GPL-3.0-or-later with EA additional terms',
                      copyright='Copyright (C) 1989-2007 Electronic Arts Inc.',
                      evidence='UPSTREAM-README.txt lines 22-92 explicitly cover images/* and include the EA terms',
                      assets=assets, generated=dict(file='tiles.png', source='tiles.xpm', width=width,
                      height=height, tileSize=16, tileCount=960,
                      rgbaSHA256=hashlib.sha256(rgba).hexdigest(), sha256=hashlib.sha256(image).hexdigest()))
    manifest = (json.dumps(provenance, ensure_ascii=False, indent=2) + '\n').encode()
    if '--check' in sys.argv:
        assert (ROOT / 'tiles.png').read_bytes() == image, 'regenerate tiles.png'
        assert (ROOT / 'provenance.json').read_bytes() == manifest, 'regenerate provenance.json'
        print('PASS original source hashes, 960 tiles, lossless pixel conversion and provenance')
    else:
        (ROOT / 'tiles.png').write_bytes(image)
        (ROOT / 'provenance.json').write_bytes(manifest)
        print('Generated original GPL atlas and provenance (960 16x16 tiles)')


if __name__ == '__main__':
    main()
