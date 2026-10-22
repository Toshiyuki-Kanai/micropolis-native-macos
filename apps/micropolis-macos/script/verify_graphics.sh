#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$APP_ROOT/../.." && pwd)"
VERIFY_DIR="$REPO_ROOT/build/macos-app-validation"
mkdir -p "$REPO_ROOT/build/original-graphics"
python3 "$APP_ROOT/script/prepare_original_graphics.py" --check
python3 "$APP_ROOT/script/prepare_gameplay_assets.py" --check
"$APP_ROOT/script/verify_engine.sh"
xcrun swiftc -parse-as-library -swift-version 6 -target arm64-apple-macosx27.0 \
  -module-cache-path "$VERIFY_DIR/module-cache" -I "$VERIFY_DIR/module" \
  "$APP_ROOT/Models/CityFrame.swift" "$APP_ROOT/Services/EngineSession.swift" \
  "$APP_ROOT/Rendering/MapGeometry.swift" "$APP_ROOT/Rendering/TilePalette.swift" \
  "$APP_ROOT/Rendering/TileAtlas.swift" "$APP_ROOT/Rendering/TerrainCanvas.swift" \
  "$APP_ROOT/Tests/GraphicsIntegration.swift" \
  "$REPO_ROOT/build/native/libmicropolis_native.a" -lc++ -o "$VERIFY_DIR/GraphicsIntegration"
"$VERIFY_DIR/GraphicsIntegration" "$REPO_ROOT"
