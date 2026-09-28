#!/bin/bash
# Package Sans-Accent for distribution: Developer ID signature + hardened runtime,
# Apple notarization, stapling, then a signed and notarized .dmg.
#
# Uses the same keychain notarization profile as Girafone ("girafone"). To create one:
#   xcrun notarytool store-credentials girafone \
#     --apple-id <apple-id> --team-id F5Q99W9462 --password <app-specific password>
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="Developer ID Application: Antoine BARTHES (F5Q99W9462)"
PROFILE=girafone
APP="dist/Sans-Accent.app"

./build.sh

# No entitlements needed: keyboard access goes through the Accessibility permission.
codesign --force --options runtime --sign "$IDENTITY" --timestamp "$APP"
codesign --verify --strict "$APP"

echo "Notarizing the app (a few minutes)…"
WORKZIP="dist/Sans-Accent-notarize.zip"
rm -f "$WORKZIP"
ditto -c -k --keepParent "$APP" "$WORKZIP"
xcrun notarytool submit "$WORKZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm -f "$WORKZIP"

# Disk image: the app + a shortcut to Applications, with the icon on the mounted volume.
VERSION=$(defaults read "$(pwd)/$APP/Contents/Info" CFBundleShortVersionString)
DMG="dist/Sans-Accent-$VERSION.dmg"
STAGE="dist/dmg-stage"
rm -rf "$STAGE" "$DMG" "$DMG.rw.dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Sans-Accent" -srcfolder "$STAGE" -ov -format UDRW "$DMG.rw.dmg" >/dev/null
MOUNT=$(hdiutil attach "$DMG.rw.dmg" -nobrowse | grep -o '/Volumes/.*' | tail -1)
cp assets/AppIcon.icns "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT" 2>/dev/null || true
hdiutil detach "$MOUNT" >/dev/null
hdiutil convert "$DMG.rw.dmg" -format UDZO -o "$DMG" >/dev/null
rm -rf "$STAGE" "$DMG.rw.dmg"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"

echo "Notarizing the disk image…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

# Same file under a fixed name: the site links to releases/latest/download/Sans-Accent.dmg.
cp "$DMG" dist/Sans-Accent.dmg

echo "✅ $DMG: notarized, stapled, ready to share."
echo "Publish: gh release create v$VERSION dist/Sans-Accent.dmg --title \"Sans-Accent $VERSION\""
