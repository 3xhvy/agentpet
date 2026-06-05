# Testing the Update Flow

This document covers how to test each layer of the update pipeline — from the
build script to a full end-to-end Sparkle update — without pushing a real release.

---

## Prerequisites

- macOS 13+, Xcode 16 / Swift 6
- Run `swift build` at least once so Sparkle's binary artifacts (including
  `sign_update`) are downloaded into `.build/artifacts/`

```bash
cd /path/to/agentpet
swift build
```

---

## Test 1 — Build & code-signing pipeline

Runs `ci-dmg.sh` without any secrets, producing an ad-hoc-signed DMG, then
verifies the bundle signature is structurally valid.

```bash
./scripts/ci-dmg.sh

# Verify the app bundle signature (deep = checks nested Sparkle XPCs too)
codesign --verify --deep --strict --verbose=2 build/AgentPet.app

# Verify the DMG exists and has a plausible size (> 2 MB)
ls -lh build/AgentPet-*.dmg
```

**Expected:**
- `codesign` prints `valid on disk` and `satisfies its Designated Requirement`
- DMG is present and larger than 2 MB

---

## Test 2 — EdDSA signing (sign_update)

Confirms the `sign_update` tool works and that the key embedded in
`scripts/AppInfo.plist` (`SUPublicEDKey`) matches the private key you intend
to use in CI.

```bash
SIGN_UPDATE="$(find .build/artifacts -name sign_update -path '*Sparkle*' | head -1)"
echo "Using: $SIGN_UPDATE"

# Sign the DMG built in Test 1
"$SIGN_UPDATE" build/AgentPet-*.dmg
```

**Expected output** (format):
```
sparkle:edSignature="<base64>=" length="<bytes>"
```

The `length` value must exactly match the DMG file size:

```bash
# Cross-check length
wc -c < build/AgentPet-*.dmg
```

**To generate a fresh test key pair** (if you haven't set up the real one yet):

```bash
"$SIGN_UPDATE" --generate-keys
# Prints two lines:
#   Public key  (ed25519): <base64>   ← put this in SUPublicEDKey in AppInfo.plist
#   Private key (ed25519): <base64>   ← put this in the SPARKLE_ED_PRIVATE_KEY CI secret
```

---

## Test 3 — Appcast XML generation (CI Python logic)

Runs the exact Python snippet used in `release.yml` against a copy of
`docs/appcast.xml` to make sure new items are inserted correctly.

```bash
# Work on a throwaway copy
cp docs/appcast.xml /tmp/appcast-test.xml

python3 - "9.9.9" "999" "TESTSIG==" "12345" "Fri, 05 Jun 2026 00:00:00 +0000" <<'PYEOF'
import sys

version, build, sig, length, date = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]

new_item = (
    "        <item>\n"
    f"            <title>{version}</title>\n"
    f"            <pubDate>{date}</pubDate>\n"
    f"            <sparkle:releaseNotesLink>https://github.com/ntd4996/agentpet/releases/tag/v{version}</sparkle:releaseNotesLink>\n"
    f"            <sparkle:version>{build}</sparkle:version>\n"
    f"            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>\n"
    "            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>\n"
    f"            <enclosure url=\"https://github.com/ntd4996/agentpet/releases/download/v{version}/AgentPet-{version}.dmg\"\n"
    f"                       sparkle:edSignature=\"{sig}\" length=\"{length}\" type=\"application/octet-stream\" />\n"
    "        </item>"
)

with open("/tmp/appcast-test.xml", "r") as f:
    content = f.read()
content = content.replace("        <item>", new_item + "\n        <item>", 1)
with open("/tmp/appcast-test.xml", "w") as f:
    f.write(content)
print("Inserted item for", version)
PYEOF

# Inspect the result — version 9.9.9 should be the first item
head -30 /tmp/appcast-test.xml
```

**Expected:** `<title>9.9.9</title>` appears before `<title>1.1.7</title>`,
with all fields (`pubDate`, `releaseNotesLink`, `sparkle:version`, `enclosure`)
present.

---

## Test 4 — End-to-end Sparkle update (full flow)

Builds two versions of the app locally and uses a local appcast file to simulate
a real update. No network access or CI needed.

> **Time estimate:** ~5 minutes

### Step 1 — Build the "old" app (the version users are running)

```bash
./scripts/build-app.sh release
cp -R build/AgentPet.app /tmp/AgentPet-old.app
```

### Step 2 — Build a fake "new" version DMG

```bash
# Temporarily bump the version
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString 9.9.9" scripts/AppInfo.plist
/usr/libexec/PlistBuddy -c "Set CFBundleVersion 999"              scripts/AppInfo.plist

./scripts/build-app.sh release

# Package into a DMG (minimal, no branding needed for this test)
NEW_DMG="$(pwd)/build/AgentPet-9.9.9.dmg"
rm -rf build/dmg-test && mkdir build/dmg-test
cp -R build/AgentPet.app build/dmg-test/
ln -sf /Applications build/dmg-test/Applications
hdiutil create -volname "AgentPet" -srcfolder build/dmg-test \
               -ov -format UDZO "$NEW_DMG" >/dev/null

# Restore the real version — do this before continuing
git checkout -- scripts/AppInfo.plist
```

### Step 3 — Sign the new DMG and capture attrs

```bash
SIGN_UPDATE="$(find .build/artifacts -name sign_update -path '*Sparkle*' | head -1)"
ATTRS="$("$SIGN_UPDATE" "$NEW_DMG")"

SIG=$(echo "$ATTRS" | python3 -c \
  "import sys,re; m=re.search(r'edSignature=\"([^\"]+)\"', sys.stdin.read()); print(m.group(1))")
LEN=$(echo "$ATTRS" | python3 -c \
  "import sys,re; m=re.search(r'length=\"([^\"]+)\"', sys.stdin.read()); print(m.group(1))")

echo "Signature: $SIG"
echo "Length:    $LEN"
```

### Step 4 — Write a local appcast

```bash
cat > /tmp/local-appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>AgentPet Local Test</title>
    <item>
      <title>9.9.9</title>
      <sparkle:version>999</sparkle:version>
      <sparkle:shortVersionString>9.9.9</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <enclosure url="file://$NEW_DMG"
                 sparkle:edSignature="$SIG" length="$LEN"
                 type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF

echo "Appcast written to /tmp/local-appcast.xml"
```

### Step 5 — Point the old app at the local appcast

```bash
/usr/libexec/PlistBuddy -c \
  "Set SUFeedURL file:///tmp/local-appcast.xml" \
  /tmp/AgentPet-old.app/Contents/Info.plist
```

### Step 6 — Launch the old app and watch for the update dialog

```bash
open /tmp/AgentPet-old.app
```

**Expected behavior:**

| What you see | What it means |
|---|---|
| App launches in menu bar | Old version (1.1.7) is running |
| "Update Available" dialog appears within a few seconds | Sparkle found 9.9.9 in the local appcast |
| Dialog shows release notes link | `sparkle:releaseNotesLink` is working |
| Clicking **Update** installs and relaunches | Full download + EdDSA verify + install pipeline works |
| After relaunch, menu bar shows new version | Sparkle applied the update correctly |

> If the dialog does not appear automatically, click the **Updates** button in
> the menu bar popover to trigger a manual check.

### Step 7 — Confirm EdDSA rejection (tamper test)

After a successful update, verify that Sparkle rejects a tampered DMG:

```bash
# Corrupt the signature in the appcast
sed -i '' 's/sparkle:edSignature="[^"]*"/sparkle:edSignature="BADSIG=="/' \
  /tmp/local-appcast.xml

# Re-launch the old app
open /tmp/AgentPet-old.app
# → Sparkle should refuse to install and show an error
```

**Expected:** Sparkle shows an error dialog and does not install the update.

---

## Test 5 — Hook path repair (stale path detection)

Confirms that `repairStaleHookPathsIfNeeded()` re-writes hook entries when the
binary path changes (simulates moving the app or switching install channels).

```bash
# 1. Build and install a hook via the app (Settings → General → Install Claude Code)
#    Then check the hook was written correctly:
cat ~/.claude/settings.json | python3 -m json.tool | grep agentpet

# 2. Simulate a path change by patching the settings.json with a fake path
python3 - <<'PYEOF'
import json, pathlib

p = pathlib.Path.home() / ".claude/settings.json"
s = json.loads(p.read_text())

def patch(hooks):
    for event, groups in hooks.items():
        for group in groups:
            for entry in group.get("hooks", []):
                if "agentpet" in entry.get("command", ""):
                    entry["command"] = '"/old/path/to/agentpet" hook --agent claudecode'
patch(s.get("hooks", {}))

p.write_text(json.dumps(s, indent=2, sort_keys=True))
print("Patched settings.json with stale path")
PYEOF

# 3. Re-launch the app — repairStaleHookPathsIfNeeded() runs on launch
open build/AgentPet.app

# 4. Wait a moment, then confirm the path was corrected
sleep 3
cat ~/.claude/settings.json | python3 -m json.tool | grep agentpet
# → Should show the current binary path, not /old/path/to/agentpet
```

---

## Cleanup

```bash
# Remove test artifacts
rm -f  /tmp/local-appcast.xml /tmp/appcast-test.xml
rm -rf /tmp/AgentPet-old.app

# Remove fake 9.9.9 DMG if still present
rm -f build/AgentPet-9.9.9.dmg build/AgentPet-9.9.9-app.zip
rm -rf build/dmg-test

# Ensure AppInfo.plist is on the correct version
git checkout -- scripts/AppInfo.plist
/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" scripts/AppInfo.plist
# → should print 1.1.7
```
