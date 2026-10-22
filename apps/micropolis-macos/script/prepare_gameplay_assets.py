#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Verify pinned original GPL sprite/sound sources; losslessly convert XPMs.
No downloads or external packages. Copyright/EA terms: bundled upstream README.
"""
import ast
import hashlib
import json
from pathlib import Path
import re
import sys
sys.dont_write_bytecode=True
from prepare_original_graphics import png

ROOT=Path(__file__).resolve().parents[1]/'Resources/OriginalGraphics/Gameplay'


def convert(source):
    strings=[ast.literal_eval(re.match(r'"(?:[^"\\]|\\.)*"',line)[0])
             for line in source.read_text().splitlines() if line.startswith('"')]
    w,h,count,cpp=map(int,strings[0].split())
    palette={}
    for line in strings[1:count+1]:
        colour=re.search(r'\bc\s+(\S+)',line[cpp:])[1]
        if colour.lower()=='none': rgba=bytes(4)
        else:
            assert colour.startswith('#') and len(colour)==13,source
            channels=[int(colour[i:i+4],16) for i in (1,5,9)]
            assert all(c%257==0 for c in channels)
            rgba=bytes([c//257 for c in channels]+[255])
        palette[line[:cpp]]=rgba
    rows=strings[1+count:]
    assert len(rows)==h and all(len(r)==w*cpp for r in rows)
    return png(w,h,b''.join(palette[r[i:i+cpp]] for r in rows for i in range(0,len(r),cpp)))


def main():
    manifest=json.loads((ROOT/'provenance.json').read_text())
    assert manifest['commit']=='c98f6b08519887b450d9be198bfca5237aab6d0c'
    generated=[]
    for item in manifest['assets']:
        source=ROOT/item['file'];data=source.read_bytes()
        assert hashlib.sha256(data).hexdigest()==item['sha256'],source
        assert hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()==item['gitBlob'],source
        if source.suffix=='.xpm':
            image=convert(source);target=source.with_suffix('.png')
            if '--check' in sys.argv: assert target.read_bytes()==image,target
            else: target.write_bytes(image)
            generated.append(dict(file=target.name,source=source.name,sha256=hashlib.sha256(image).hexdigest()))
    out=(json.dumps(generated,indent=2)+'\n').encode()
    if '--check' in sys.argv: assert (ROOT/'generated.json').read_bytes()==out
    else: (ROOT/'generated.json').write_bytes(out)
    print(f"PASS {len(manifest['assets'])} GPL asset hashes, {len(generated)} lossless transparent sprite frames")


if __name__=='__main__': main()
