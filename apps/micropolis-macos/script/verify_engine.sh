#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$APP_ROOT/../.." && pwd)"
VERIFY_DIR="$REPO_ROOT/build/macos-app-validation"
mkdir -p "$VERIFY_DIR/module" "$REPO_ROOT/build/gameplay-validation"
make -C "$REPO_ROOT" -f packages/micropolis-engine/native.mk -j4 \
  CXX='xcrun clang++ -arch arm64' CC='xcrun clang -arch arm64' test
cat > "$VERIFY_DIR/module/module.modulemap" <<MODULE
module MicropolisNative {
  header "$REPO_ROOT/packages/micropolis-engine/native/include/micropolis_native.h"
  export *
}
MODULE
xcrun swiftc -parse-as-library -swift-version 6 -target arm64-apple-macosx27.0 \
  -module-cache-path "$VERIFY_DIR/module-cache" -I "$VERIFY_DIR/module" \
  "$APP_ROOT/Models/CityFrame.swift" "$APP_ROOT/Models/CityModel.swift" \
  "$APP_ROOT/Services/EngineSession.swift" "$APP_ROOT/Rendering/MapGeometry.swift" \
  "$APP_ROOT/Tests/EngineIntegration.swift" \
  "$REPO_ROOT/build/native/libmicropolis_native.a" -lc++ -o "$VERIFY_DIR/EngineIntegration"
"$VERIFY_DIR/EngineIntegration" "$REPO_ROOT"
