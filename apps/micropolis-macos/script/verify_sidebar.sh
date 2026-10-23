#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Requires a logged-in macOS GUI session. Uses an independent test window.
set -euo pipefail
APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$APP_ROOT/../.." && pwd)"
VERIFY_DIR="$REPO_ROOT/build/macos-app-validation"
"$APP_ROOT/script/verify_engine.sh"
xcrun swiftc -parse-as-library -swift-version 6 -target arm64-apple-macosx27.0 \
  -module-cache-path "$VERIFY_DIR/module-cache" -I "$VERIFY_DIR/module" \
  "$APP_ROOT"/Models/*.swift "$APP_ROOT"/Services/*.swift \
  "$APP_ROOT"/Rendering/*.swift "$APP_ROOT"/Views/*.swift \
  "$APP_ROOT/Tests/SidebarLayout.swift" \
  "$REPO_ROOT/build/native/libmicropolis_native.a" -lc++ -o "$VERIFY_DIR/SidebarLayout"
"$VERIFY_DIR/SidebarLayout"
