#!/usr/bin/env bash
# Builds, Developer ID-signs, notarizes, and staples a distributable DMG.
#
# One-time setup (your Apple credentials, run it yourself):
#   xcrun notarytool store-credentials agentpet \
#     --apple-id "<your-apple-id-email>" \
#     --team-id 9D7HY2JCGN \
#     --password "<app-specific-password>"
# Create the app-specific password at https://appleid.apple.com → Sign-In & Security.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/build/AgentPet.app"
IDENTITY="Developer ID Application: Dat Nguyen (9D7HY2JCGN)"
PROFILE="${NOTARY_PROFILE:-agentpet}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' scripts/AppInfo.plist)"

echo "==> Building AgentPet.app"
./scripts/build-app.sh release

echo "==> Signing with Developer ID (hardened runtime)"
# Sign any nested bundles first, then the main executable, then the app.
while IFS= read -r -d '' nested; do
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$nested"
done < <(find "$APP/Contents/Resources" -name "*.bundle" -print0 2>/dev/null)
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/MacOS/agentpet"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Building DMG"
DMG="$ROOT/build/AgentPet-$VERSION.dmg"
STAGE="$ROOT/build/dmg"
rm -f "$DMG"; rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/AgentPet.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "AgentPet" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo "==> Notarizing (this can take a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler staple "$APP"

echo "==> Done"
echo "DMG:    $DMG"
echo "SHA256: $(shasum -a 256 "$DMG" | awk '{print $1}')"
