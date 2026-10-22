#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# No downloads/Gradle plugins. Requires separately obtained, pinned v2.0.0 source.
set -euo pipefail
APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$APP_ROOT/../.." && pwd)"
JAVA_SOURCE="${1:?Pass the extracted official v2.0.0 source directory}"
OUTPUT="$REPO_ROOT/build/micropolisj-parity"
python3 - "$JAVA_SOURCE" "$APP_ROOT/Tests/MicropolisJ-v2-source-hashes.json" <<'PY'
import hashlib,json,sys
from pathlib import Path
root=Path(sys.argv[1])
manifest=json.loads(Path(sys.argv[2]).read_text())
for name,expected in manifest.items():
    assert hashlib.sha256((root/name).read_bytes()).hexdigest()==expected,name
actual={str(p.relative_to(root)) for p in root.glob('src/main/java/micropolisj/engine/*.java')}
assert actual=={n for n in manifest if n.endswith('.java')},'unexpected Java source'
print('PASS fixed MicropolisJ v2.0.0 engine sources and tile metadata hashes')
PY
make -C "$REPO_ROOT" -f packages/micropolis-engine/native.mk -j4 CXX='xcrun clang++ -arch arm64' CC='xcrun clang -arch arm64' test
mkdir -p "$OUTPUT/java-classes"
javac -d "$OUTPUT/java-classes" "$JAVA_SOURCE"/src/main/java/micropolisj/engine/*.java "$APP_ROOT/Tests/JavaSaveCompatibility.java"
java -Djava.awt.headless=true -cp "$OUTPUT/java-classes:$JAVA_SOURCE/src/main/resources" JavaSaveCompatibility "$REPO_ROOT/build/native/parity-classic.cty" "$OUTPUT/java-resaved.cty"
xcrun clang -arch arm64 -I "$REPO_ROOT/packages/micropolis-engine/native/include" -c "$REPO_ROOT/packages/micropolis-engine/tests/native/java_save_probe.c" -o "$OUTPUT/java-save-probe.o"
xcrun clang++ -arch arm64 "$OUTPUT/java-save-probe.o" "$REPO_ROOT/build/native/libmicropolis_native.a" -o "$OUTPUT/java-save-probe"
"$OUTPUT/java-save-probe" "$REPO_ROOT/build/native/parity-classic.cty" "$OUTPUT/java-resaved.cty"
