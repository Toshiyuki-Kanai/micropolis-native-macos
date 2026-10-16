#!/usr/bin/env python3
"""Build updated WASM and run unchanged web tests in an ignored app copy.
Requires em++, node and the existing workspace node_modules. No make install.
SPDX-License-Identifier: GPL-3.0-or-later; see repository GPL/EA notices.
"""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--emxx', default='em++')
parser.add_argument('--out', default='build/wasm-regression')
args = parser.parse_args()
root = Path(__file__).resolve().parents[4]
engine = root / 'packages/micropolis-engine'
out = (root / args.out).resolve()
if not out.is_relative_to(root / 'build'):
    parser.error('--out must be inside the repository build/ directory')
out.mkdir(parents=True, exist_ok=True)
original = root / 'apps/micropolis/src/lib'
protected = [original / ('micropolisengine.' + s) for s in ('js', 'wasm', 'data')]
before = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in protected}

def run(command, log, cwd=root):
    with (out / log).open('w') as stream:
        result = subprocess.run(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT)
    if result.returncode:
        print((out / log).read_text()[-10000:])
        raise SystemExit(result.returncode)

try:
    module = out / 'micropolisengine.mjs'
    core = sorted((engine / 'src').glob('*.cpp'))
    run([args.emxx, '-std=c++17', '-O1', '-fPIC', *map(str, core), '-lembind',
         '-sMODULARIZE=1', '-sEXPORT_ES6=1', '-sENVIRONMENT=web,worker,node',
         '-sALLOW_MEMORY_GROWTH=1',
         '-sEXPORTED_RUNTIME_METHODS=["HEAPU16","wasmMemory"]',
         '--preload-file', str(root / 'content/micropolis/cities') + '@cities/',
         '-o', str(module)], 'compile.log')
    snapshot = out / 'repo'
    app = snapshot / 'apps/micropolis'
    if app.exists():
        shutil.rmtree(app)
    app.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(root / 'apps/micropolis', app, symlinks=True,
                    ignore=shutil.ignore_patterns('node_modules', '.svelte-kit', 'build',
                                                  'website', '.jekyll-cache'))
    for name in ('node_modules', 'packages', 'content'):
        link = snapshot / name
        if not link.exists():
            link.symlink_to(root / name, target_is_directory=True)
    for name in ('pnpm-workspace.yaml', 'package.json'):
        shutil.copy2(root / name, snapshot / name)
    other = snapshot / 'apps/vitamoospace'
    if not other.exists():
        other.symlink_to(root / 'apps/vitamoospace', target_is_directory=True)
    (app / 'node_modules').symlink_to(root / 'apps/micropolis/node_modules', target_is_directory=True)
    lib = app / 'src/lib'
    shutil.copy2(module, lib / 'micropolisengine.js')
    for extension in ('wasm', 'data'):
        shutil.copy2(out / ('micropolisengine.' + extension), lib / ('micropolisengine.' + extension))
    run(['node', str(app / 'node_modules/vitest/vitest.mjs'), 'run'], 'web-tests.log', app)
    print('PASS rebuilt WASM + unchanged web/CLI suite (isolated app copy)')

    # Run the same C++ core regressions in wasm32, including the 32-bit file
    # boundary. Exclude browser bindings; use the no-op frontend adapter.
    core = [p for p in core if p.name not in ('emscripten.cpp', 'callback.cpp')]
    pre = out / 'pre.js'
    pre.write_text("Module['preRun'] = Module['preRun'] || []; Module['preRun'].push(function() { FS.mkdir('/output'); });\n")
    program = out / 'core-test.cjs'
    run([args.emxx, '-std=c++17', '-O1', '-fexceptions', '-sALLOW_MEMORY_GROWTH=1',
         '-sSTACK_SIZE=1048576', '-sSTACK_OVERFLOW_CHECK=2',
         '-sENVIRONMENT=node', '-I' + str(engine / 'src'),
         '-I' + str(engine / 'native/include'), *map(str, core),
         str(engine / 'native/callback.cpp'), str(engine / 'native/api.cpp'),
         str(engine / 'tests/native/core_test.cpp'), '-lembind',
         '--preload-file', str(root / 'content/micropolis/cities') + '@/content/micropolis/cities',
         '--pre-js', str(pre), '-o', str(program)], 'core-compile.log')
    run(['node', str(program), '/', '/output'], 'core-tests.log', out)
    print('PASS wasm32 shared core regressions: save bytes, funding, sprites, cities, ticks')
finally:
    after = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in protected}
    if before != after:
        raise RuntimeError('Original WASM artifacts changed!')
    print('Original JS/WASM/data hashes unchanged')
