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

# Sign with a stable identity if one exists. This is what keeps the Screen Recording
# and Accessibility grants alive across rebuilds: a certificate gives the bundle a
# designated requirement of "identifier + certificate leaf", whereas an ad-hoc signature
# has no team identifier and forces macOS to key permissions to the binary's cdhash --
# which changes every single build, so every build has to be re-granted by hand.
IDENTITY="GestureBind Local Dev"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  codesign --force --sign "$IDENTITY" --identifier com.gesturebind.app "$APP"
else
  codesign --force --sign - --identifier com.gesturebind.app "$APP" >/dev/null 2>&1 || true
  cat >&2 <<'WARN'
warning: signed ad-hoc. macOS will ask for Screen Recording and Accessibility again
         after every rebuild. Run ./make-signing-identity.sh once to stop that.
WARN
fi

echo "Built $APP"
