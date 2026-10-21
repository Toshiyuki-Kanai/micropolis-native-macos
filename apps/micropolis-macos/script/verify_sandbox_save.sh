#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Requires a logged-in macOS GUI session. Does not touch the running game.
set -euo pipefail
APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$APP_ROOT/../.." && pwd)"
"$APP_ROOT/script/verify_engine.sh"
VERIFY_DIR="$REPO_ROOT/build/macos-app-validation"
PROBE="$VERIFY_DIR/SaveSandboxProbe.app"
BUNDLE_ID=org.micropolis.SaveSandboxProbe
mkdir -p "$PROBE/Contents/MacOS"
cat > "$PROBE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleExecutable</key><string>SaveSandboxProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDocumentTypes</key><array><dict>
<key>CFBundleTypeName</key><string>Micropolis City</string>
<key>CFBundleTypeRole</key><string>Editor</string>
<key>CFBundleTypeExtensions</key><array><string>cty</string></array>
</dict></array></dict></plist>
PLIST
xcrun swiftc -parse-as-library -swift-version 6 -target arm64-apple-macosx27.0 \
  -module-cache-path "$VERIFY_DIR/module-cache" -I "$VERIFY_DIR/module" \
  "$APP_ROOT/Models/CityFrame.swift" "$APP_ROOT/Services/EngineSession.swift" \
  "$APP_ROOT/Tests/SandboxSaveProbe.swift" \
  "$REPO_ROOT/build/native/libmicropolis_native.a" -lc++ \
  -o "$PROBE/Contents/MacOS/SaveSandboxProbe"
codesign --force --sign - --entitlements "$APP_ROOT/App/MicropolisMac.entitlements" "$PROBE"
FIXTURE="$VERIFY_DIR/保存テスト $(uuidgen).cty"
cp "$REPO_ROOT/build/native/gameplay-grown.cty" "$FIXTURE"
RESULT="$HOME/Library/Containers/$BUNDLE_ID/Data/Library/Caches/$(basename "$FIXTURE").result"
open -n -a "$PROBE" "$FIXTURE"
for ((attempt=0; attempt<30; attempt++)); do
  if [[ -f "$RESULT" ]]; then
    cat "$RESULT"
    [[ "$(cat "$RESULT")" == PASS* ]]
    exit
  fi
  sleep 1
done
echo "FAIL sandbox save probe timed out" >&2
exit 1
