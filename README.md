<div align="center">
  <img src="assets/banner.png" alt="AgentPet" width="100%" />
  <p>
    <img src="https://img.shields.io/badge/platform-macOS%2013%2B%20%C2%B7%20Windows%2010%2F11-black" alt="macOS 13+ · Windows 10/11" />
    <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT" />
    <img src="https://img.shields.io/badge/Swift-SwiftUI-orange" alt="Swift" />
    <a href="https://github.com/ntd4996/agentpet/actions"><img src="https://github.com/ntd4996/agentpet/actions/workflows/ci.yml/badge.svg" alt="CI" /></a>
    <a href="https://github.com/ntd4996/agentpet"><img src="https://img.shields.io/github/stars/ntd4996/agentpet?style=social" alt="GitHub stars" /></a>
  </p>
  <p><b>If AgentPet helps your workflow, please <a href="https://github.com/ntd4996/agentpet">give it a star</a> — it really helps!</b></p>
  <p>
    <b>English</b> ·
    <a href="docs/readme/README.vi.md">Tiếng Việt</a> ·
    <a href="docs/readme/README.zh-Hans.md">简体中文</a> ·
    <a href="docs/readme/README.ja.md">日本語</a>
  </p>
</div>

Run several coding agents at once (Claude Code, Codex, ...) and AgentPet tells you, at a glance, which one is **working**, which one is **done**, and which one is **waiting for your input**, so you stop tab-hunting across terminals. A little pet floats on your desktop and reacts to it all.

## Why

Running multiple agents in parallel means constantly switching windows to check who needs you. AgentPet surfaces that in two places:

- **Menu bar monitor** for the details: every running agent, its state, what it's doing, and a live timer.
- **Desktop pet** for an ambient signal you can read without breaking focus.

## Features

- **Multi-agent monitor** in the menu bar: live list of every agent with a colored status dot, the project, what it's doing (running tool / waiting reason), and a per-state timer that counts in real time.
- **At-a-glance menu bar icon**: shows the number of running agents, and turns **orange with a count** when one needs your input.
- **Desktop pet** that reacts to the aggregate state (working / waiting / done / celebrate), with an optional **chat bubble** (built-in or fully custom messages).
- **Native notifications** when an agent finishes or needs input.
- **Claude Code, Codex, Gemini CLI, Cursor, opencode, Windsurf & Antigravity** integration via hooks, with one-tap install from Settings (precise working / waiting / done / idle, including "needs your input"). GLM (Z.AI) works through Claude Code automatically. Cursor, Windsurf and Antigravity report working/done (they have no "needs input" hook).
- **Universal wrapper** `agentpet run -- <command>` to monitor *any* CLI agent (working/done), no per-agent setup.
- **Raise your pet (tamagotchi)**: your companion is fed by real work, the tokens your agents burn and the sessions they finish. It earns XP, levels up, and evolves through five stages (Hatchling → Companion → Scout → Hero → Legend). Every pet keeps its own level.
- **Stats HUD**: right-click the pet for a game-style card, level, XP, hunger, a 7-day burn chart, and your live **Claude / Codex subscription limits read directly from your sign-ins** (no extra app needed).
- **Web profile & leaderboard**: optionally sign in with GitHub to show your companions at [agentpet.thenightwatcher.online](https://agentpet.thenightwatcher.online/profile) and climb the community [leaderboard](https://agentpet.thenightwatcher.online/leaderboard) (by level, sessions, or tokens). Fully optional, everything works offline if you never connect.
- **Pet system**: browse an online pet library and download with one click, map each animation to a state, resize, and customise chat lines.
- **Polished, native Settings** (tabbed, dark) that never steals focus.

## Screenshots

<div align="center">
  <img src="assets/screenshot-menubar.png" width="360" alt="Menu bar monitor" />
  <img src="assets/screenshot-settings.png" width="360" alt="Settings" />
  <img src="assets/screenshot-pet.png" width="360" alt="Pet" />
  <img src="assets/screenshot-care.png" width="360" alt="Pet care: level, XP and subscription limits" />
  <br/>
  <img src="assets/screenshot-leaderboard.png" width="600" alt="Community leaderboard of raised companions" />
  <br/>
  <img src="assets/demo.gif" width="600" alt="Pet reacting to agent activity" />
</div>

## Requirements

- **macOS 13 Ventura or later** (macOS 14 Sonoma+ recommended; Apple Silicon and Intel both supported), or **Windows 10 / 11 (64-bit)**.
- To build the macOS app from source: Xcode 16 / Swift 6. The Windows app lives under [`windows/`](windows/) (Tauri + Rust).

## Install

### macOS , Homebrew

```bash
brew install --cask ntd4996/tap/agentpet
```

### macOS , direct download

Grab the latest `AgentPet.dmg` from [Releases](https://github.com/ntd4996/agentpet/releases/latest), open it, and drag AgentPet to Applications.

### Windows

Download the latest installer or portable build from the [website](https://agentpet.thenightwatcher.online/install) or the [`win-` releases](https://github.com/ntd4996/agentpet/releases). The first launch may show a SmartScreen warning (the early Windows build isn't code-signed yet), click **More info → Run anyway**. It installs per-user (no admin) and auto-updates.

### Build from source (macOS)

```bash
git clone https://github.com/ntd4996/agentpet.git
cd agentpet
./scripts/build-app.sh release
open build/AgentPet.app
```

macOS builds are Developer ID-signed and notarized by Apple, so they open without a Gatekeeper warning. AgentPet also updates itself: it checks for new versions automatically, and you can update in-app from the menu bar **Updates** button.

On first launch, open **Settings → General** and click **Install** next to Claude Code, then **Enable** notifications.

### Uninstall

1. In **Settings → General**, click **Remove** next to each agent you connected (this strips AgentPet's hooks from the agents' config so they don't error after the app is gone).
2. Remove the app and its data:

```bash
brew uninstall --cask agentpet          # or drag /Applications/AgentPet.app to Trash
rm -rf ~/.agentpet                       # downloaded pets + state
rm -f  ~/Library/Preferences/com.agentpet.app.plist
```

## Usage

**Claude Code** (recommended): install the hook from Settings. AgentPet then reflects each session's real state (including "waiting for input").

**Any other CLI agent**: wrap it.

```bash
agentpet run -- <your-agent-command>     # e.g. agentpet run -- aider
```

The session shows as *working* while it runs and *done* when it exits.

## Pets

Pets use the open Codex pet-pack format (`pet.json` + an 8×9 spritesheet). You can:

- **Browse** the online library and download a pet with one click (Settings → Pet → Browse pets).
- **Map animations**: pick which sheet animation plays for each state.
- **Delete** pets you no longer want.

A starter pet is installed automatically on first launch. AgentPet bundles no pet art; packs are added at runtime.

## Roadmap

- Notarized DMG + Homebrew cask
- Click an agent to reveal its terminal
- Per-project pets

## Community ports

AgentPet is macOS-only, but the community has reimagined it for other platforms:

- **Linux (Rust + GTK4)** , [agentpet-linux](https://github.com/tranhuuhuy297/agentpet-linux) by [@tranhuuhuy297](https://github.com/tranhuuhuy297). An independent, from-scratch port for Ubuntu (Claude Code + Codex).

These are separate community projects, not maintained here. Building one? Open an issue and we'll link it.

## Tech

Swift + SwiftUI, a Unix-socket daemon for agent events, and a tiny CLI helper, all in one SwiftPM package. See [`docs/specs`](docs/specs) for the design.

## Support

If AgentPet saves you some tab-hunting, here's how to help:

- ⭐ **[Star the repo](https://github.com/ntd4996/agentpet)** so more people find it.
- ☕ **[Buy me a coffee](https://buymeacoffee.com/ntd4996)** if you'd like to fuel more features.

Built by **[Nguyễn Thành Đạt (@ntd4996)](https://github.com/ntd4996)**.

## Acknowledgements

The Codex pet-pack format and the online pet library are provided by
**[Petdex](https://github.com/crafter-station/petdex)** (MIT). AgentPet is an
independent, interop client: it reads packs in Petdex's format and lets you
download them from Petdex's public API. AgentPet bundles no pet art; every pet
asset is owned by its respective submitter under their own license. If you hold
rights to a character, please direct takedowns to Petdex.

## License

MIT, see [LICENSE](LICENSE). Application code only; pet assets are not part of this repository.
