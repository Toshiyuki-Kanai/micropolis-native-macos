#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
MODE="${1:-run}"
case "$MODE" in run|--debug|--logs|--telemetry|--verify) ;; *) echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;; esac
APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$APP_ROOT/../.." && pwd)"
DERIVED="$REPO_ROOT/build/micropolis-macos"
APP_BUNDLE="$DERIVED/Build/Products/Debug/MicropolisMac.app"
# Preserve existing sessions and their unsaved changes; launch a separate instance.
xcodebuild -project "$APP_ROOT/MicropolisMac.xcodeproj" -scheme MicropolisMac \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED" build
case "$MODE" in
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/MicropolisMac" ;;
  --logs|--telemetry)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'process == "MicropolisMac"'
    ;;
  --verify)
    /usr/bin/open -n "$APP_BUNDLE"
    sleep 2
    pgrep -x MicropolisMac
    ;;
esac
