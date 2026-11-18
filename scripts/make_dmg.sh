#!/usr/bin/env bash
# Construit un DMG « glisser-déposer » prêt à tester.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" packaging/Info.plist)
APP="dist/MissionTokenLive.app"
DMG="dist/MissionTokenLive-${VERSION}.dmg"
STAGE="dist/dmg-stage"

[ -d "$APP" ] || { echo "Lance d'abord ./scripts/build.sh"; exit 1; }

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "MissionTokenLive" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGE"

echo "OK : $DMG"
du -h "$DMG" | cut -f1
