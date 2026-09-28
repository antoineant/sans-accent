#!/bin/bash
# Build the binary, assemble Sans-Accent.app, sign it and install it in /Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --product SansAccent

APP="dist/Sans-Accent.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SansAccent "$APP/Contents/MacOS/SansAccent"
cp Info.plist "$APP/Contents/Info.plist"
cp accent_dict.tsv assets/AppIcon.icns "$APP/Contents/Resources/"
cp -R Localization/*.lproj "$APP/Contents/Resources/"
# Same Developer ID identity on every build, so the Accessibility permission survives rebuilds.
# Without that certificate (contributors), sign ad hoc: macOS will ask for access again after each build.
IDENTITY="Developer ID Application: Antoine BARTHES (F5Q99W9462)"
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi

# One canonical copy, so macOS doesn't grant permissions to a stale one.
pkill -x SansAccent || true
rm -rf /Applications/Sans-Accent.app
cp -R "$APP" /Applications/Sans-Accent.app

echo "Build OK -> /Applications/Sans-Accent.app"
echo "Launch with: open /Applications/Sans-Accent.app"
