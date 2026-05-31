<div align="center">
  <img src="assets/icon.png" width="120" alt="AgentPet" />
  <h1>AgentPet</h1>
  <p><b>A native macOS menu bar app that watches your AI coding agents, with a desktop pet that reacts in real time.</b></p>
  <p>
    <img src="https://img.shields.io/badge/platform-macOS%2013%2B-black" alt="macOS 13+" />
    <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT" />
    <img src="https://img.shields.io/badge/Swift-SwiftUI-orange" alt="Swift" />
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
- **Claude Code, Codex & Gemini CLI** integration via hooks, with one-tap install from Settings (precise working / waiting / done / idle, including "needs your input").
- **Universal wrapper** `agentpet run -- <command>` to monitor *any* CLI agent (working/done), no per-agent setup.
- **Pet system**: import pet packs (pet.json + spritesheet), browse an online pet library, map each animation to a state, resize, and customise chat lines.
- **Polished, native Settings** (tabbed, dark) that never steals focus.

## Install

> Notarized release / Homebrew coming soon. For now, build from source (Xcode 15+ / Swift 6).

```bash
git clone https://github.com/ntd4996/agentpet.git
cd agentpet
./scripts/build-app.sh release
open build/AgentPet.app
```

On first launch, open **Settings → General** and click **Install** next to Claude Code, then **Enable** notifications.

## Usage

**Claude Code** (recommended): install the hook from Settings. AgentPet then reflects each session's real state (including "waiting for input").

**Any other CLI agent**: wrap it.

```bash
agentpet run -- <your-agent-command>     # e.g. agentpet run -- aider
```

The session shows as *working* while it runs and *done* when it exits.

## Pets

Pets use the open Codex pet-pack format (`pet.json` + an 8×9 spritesheet). You can:

- **Import** a pet folder or `.zip` (Settings → Pet → Import).
- **Browse** the online library and download with one click.
- **Map animations**: pick which sheet animation plays for each state.

AgentPet does not bundle any pet art; packs are added at runtime by you.

## Roadmap

- Notarized DMG + Homebrew cask
- Click an agent to reveal its terminal
- Per-project pets

## Tech

Swift + SwiftUI, a Unix-socket daemon for agent events, and a tiny CLI helper, all in one SwiftPM package. See [`docs/specs`](docs/specs) for the design.

## Acknowledgements

The Codex pet-pack format and the online pet library are provided by
**[Petdex](https://github.com/crafter-station/petdex)** (MIT). AgentPet is an
independent, interop client: it reads packs in Petdex's format and lets you
download them from Petdex's public API. AgentPet bundles no pet art; every pet
asset is owned by its respective submitter under their own license. If you hold
rights to a character, please direct takedowns to Petdex.

## License

MIT, see [LICENSE](LICENSE). Application code only; pet assets are not part of this repository.
