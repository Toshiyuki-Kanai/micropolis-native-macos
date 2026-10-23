#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Requires a logged-in macOS GUI session. Never closes an existing game window.
set -euo pipefail
APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$APP_ROOT/../.." && pwd)"
VERIFY_DIR="$REPO_ROOT/build/macos-app-validation"
"$APP_ROOT/script/verify_engine.sh"
xcrun swiftc -parse-as-library -swift-version 6 -target arm64-apple-macosx27.0 \
  -module-cache-path "$VERIFY_DIR/module-cache" -I "$VERIFY_DIR/module" \
  "$APP_ROOT/Models/AppText.swift" "$APP_ROOT/Models/CityFrame.swift" "$APP_ROOT/Models/CityModel.swift" \
  "$APP_ROOT/Services/EngineSession.swift" "$APP_ROOT/Rendering/MapGeometry.swift" \
  "$APP_ROOT/Services/CityFiles.swift" "$APP_ROOT/Services/CityWindowBridge.swift" \
  "$APP_ROOT/Tests/WindowLifecycle.swift" \
  "$REPO_ROOT/build/native/libmicropolis_native.a" -lc++ -o "$VERIFY_DIR/WindowLifecycle"
RESULT="$("$VERIFY_DIR/WindowLifecycle")"
printf '%s\n' "$RESULT"
[[ "$RESULT" == *"PASS window lifecycle:"* ]]
