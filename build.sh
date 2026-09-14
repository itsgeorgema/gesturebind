#!/bin/bash
# Builds GestureBind.app from Sources/. No Xcode project required.
set -euo pipefail
cd "$(dirname "$0")"

APP="GestureBind.app"
ARCH="$(uname -m)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O \
  -target "${ARCH}-apple-macos13.0" \
  -framework AppKit -framework SwiftUI -framework ServiceManagement \
  -o "$APP/Contents/MacOS/GestureBind" \
  Sources/*.swift

cp Info.plist "$APP/Contents/Info.plist"

# An ad-hoc signature gives the bundle a stable identity, so macOS keeps the
# Accessibility and Screen Recording permissions across rebuilds instead of
# asking for them again every time.
codesign --force --sign - --identifier com.gesturebind.app "$APP" >/dev/null 2>&1 \
  || echo "warning: ad-hoc codesign failed; permissions may reset on each rebuild"

echo "Built $APP"
