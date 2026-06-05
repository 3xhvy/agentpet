#!/usr/bin/env bash
# Builds AgentPet.app and a DMG. Signs with a Developer ID and notarizes when
# the corresponding env vars (from CI secrets) are present; otherwise produces
# an ad-hoc-signed DMG. Used by .github/workflows/release.yml.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/AgentPet.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' scripts/AppInfo.plist)"

./scripts/build-app.sh release

if [ -n "${SIGN_IDENTITY:-}" ]; then
    echo "==> Signing with Developer ID (inside-out: Sparkle XPCs first)"
    # Sparkle ships nested XPC services that must be signed before the outer
    # framework and app, otherwise deep verification fails at runtime.
    SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
    if [ -d "$SPARKLE" ]; then
        SV="$SPARKLE/Versions/B"
        for nested in \
            "$SV/XPCServices/Downloader.xpc" \
            "$SV/XPCServices/Installer.xpc" \
            "$SV/Autoupdate" \
            "$SV/Updater.app"; do
            [ -e "$nested" ] && codesign --force --options runtime --timestamp \
                --sign "$SIGN_IDENTITY" "$nested"
        done
        codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$SPARKLE"
    fi
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP/Contents/MacOS/agentpet"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
    codesign --verify --strict "$APP"
fi

DMG="build/AgentPet-$VERSION.dmg"
STAGE="build/dmg"
rm -f "$DMG"; rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/AgentPet.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "AgentPet" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

if [ -n "${AC_API_KEY_P8:-}" ] && [ -n "${AC_KEY_ID:-}" ] && [ -n "${AC_ISSUER_ID:-}" ]; then
    echo "==> Notarizing"
    echo "$AC_API_KEY_P8" | base64 --decode > /tmp/ac_key.p8
    xcrun notarytool submit "$DMG" --key /tmp/ac_key.p8 --key-id "$AC_KEY_ID" --issuer "$AC_ISSUER_ID" --wait
    xcrun stapler staple "$DMG"
    rm -f /tmp/ac_key.p8
fi

echo "==> Built $DMG"
shasum -a 256 "$DMG"

# Generate the EdDSA signature for the Sparkle appcast if the private key is
# provided via SPARKLE_ED_PRIVATE_KEY. The sign_update tool ships inside the
# Sparkle binary artifact that SwiftPM downloads during the build.
if [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
    echo "==> Signing DMG for Sparkle appcast"
    SIGN_UPDATE="$(find .build/artifacts -name sign_update -path '*Sparkle*' 2>/dev/null | head -1)"
    if [ -z "$SIGN_UPDATE" ]; then
        echo "warning: sign_update not found; run swift build first" >&2
    else
        KEY_FILE="$(mktemp)"
        echo "$SPARKLE_ED_PRIVATE_KEY" > "$KEY_FILE"
        ED_ATTRS="$("$SIGN_UPDATE" --ed-key-file "$KEY_FILE" "$DMG")"
        rm -f "$KEY_FILE"
        # Write attrs to a file so the CI workflow can read them without re-parsing stdout.
        echo "$ED_ATTRS" > build/sparkle-attrs.txt
        echo "Sparkle attrs: $ED_ATTRS"
    fi
fi
