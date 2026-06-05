# Releasing

## How the update flow works

```
You                    CI (release.yml)              Users' running app
───                    ────────────────              ──────────────────
1. Bump version
   AppInfo.plist
   (CFBundleShortVersionString
    + CFBundleVersion)
        │
2. git tag vX.Y.Z
   git push --tags
        │
        ▼
                  3. Build universal DMG
                     (build-app.sh → ci-dmg.sh)
                        │
                  4. Sign Sparkle XPCs +
                     app with Developer ID
                     (if MACOS_* secrets set)
                        │
                  5. Notarize + staple DMG
                     (if AC_* secrets set)
                        │
                  6. Sign DMG with EdDSA key
                     → build/sparkle-attrs.txt
                     (if SPARKLE_ED_PRIVATE_KEY set)
                        │
                  7. Upload DMG to
                     GitHub Release
                        │
                  8. Prepend <item> to
                     docs/appcast.xml
                     (version, pubDate,
                      releaseNotesLink,
                      edSignature, length)
                     Commit + push to main
                     → GitHub Pages serves it
                        │
                        ▼
                                          9. Sparkle polls
                                             appcast.xml
                                             (background, ~24h)
                                                │
                                          10. "Update available"
                                              dialog with changelog
                                                │
                                          11. User clicks Update
                                              Sparkle downloads +
                                              verifies EdDSA sig
                                              installs + relaunches
```

## Releasing a new version (step by step)

**1. Bump the version** in `scripts/AppInfo.plist`:

```xml
<key>CFBundleShortVersionString</key>
<string>1.2.0</string>        <!-- human-readable semver -->
<key>CFBundleVersion</key>
<string>120</string>           <!-- integer: strip dots (1.2.0 → 120) -->
```

**2. Commit and tag:**

```bash
git add scripts/AppInfo.plist
git commit -m "chore: bump version to 1.2.0"
git tag v1.2.0
git push origin main --tags
```

CI takes it from there. If the signing and EdDSA secrets are configured, the
appcast is updated automatically and users will see the update within ~24 hours.

## One-time secret setup

Add these to **Settings → Secrets and variables → Actions** in the repo:

| Secret | Required for | What it is |
|---|---|---|
| `MACOS_CERT_P12` | Code signing | base64 of your "Developer ID Application" .p12 |
| `MACOS_CERT_PASSWORD` | Code signing | Password for that .p12 |
| `MACOS_SIGN_IDENTITY` | Code signing | e.g. `Developer ID Application: Your Name (TEAMID)` |
| `AC_API_KEY_P8` | Notarization | base64 of an App Store Connect API key (.p8) |
| `AC_KEY_ID` | Notarization | The API key's Key ID |
| `AC_ISSUER_ID` | Notarization | The API key's Issuer ID |
| `SPARKLE_ED_PRIVATE_KEY` | Auto-update delivery | EdDSA private key for `sign_update` (see below) |

Without the signing/notarization secrets, CI still builds a working DMG — users
just need to clear Gatekeeper quarantine once (`xattr -dr com.apple.quarantine AgentPet.app`).

Without `SPARKLE_ED_PRIVATE_KEY`, the appcast is not updated automatically.
You can still update it manually by running `./scripts/release.sh` locally.

### Generating the Sparkle EdDSA key pair (one time)

```bash
# After swift build, the sign_update tool is in .build/artifacts
SIGN_UPDATE="$(find .build/artifacts -name sign_update -path '*Sparkle*' | head -1)"

# Generate a new key pair; prints both keys to stdout
"$SIGN_UPDATE" --generate-keys
```

- Copy the **private key** → add as `SPARKLE_ED_PRIVATE_KEY` repo secret
- Copy the **public key** → paste into `scripts/AppInfo.plist` as `SUPublicEDKey`

The public key is already in the plist (`SUPublicEDKey`). Only regenerate if you
need to rotate keys; all existing users must update before the rotation or their
app can no longer verify future updates.

## What each script does

| Script | When it runs | What it does |
|---|---|---|
| `scripts/build-app.sh` | CI + local | Compiles universal binary, assembles `.app`, ad-hoc signs |
| `scripts/ci-dmg.sh` | CI | Calls `build-app.sh`, Developer ID signs (inside-out for Sparkle XPCs), notarizes, EdDSA-signs for Sparkle |
| `scripts/release.sh` | Local only | Full signed + notarized release using a stored keychain profile; also prints the appcast `<item>` snippet |

## How Sparkle verifies updates

When a user's app downloads an update DMG, Sparkle checks the EdDSA signature
in the appcast against `SUPublicEDKey` in the running app's bundle. If the
signature doesn't match, the update is rejected and the app is not touched. This
is why both `sign_update` (CI secret) and `SUPublicEDKey` (plist) must come from
the same key pair.
