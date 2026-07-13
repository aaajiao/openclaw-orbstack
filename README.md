# OpenClaw OrbStack

One-click [OpenClaw](https://github.com/openclaw/openclaw) deployment on macOS via an OrbStack VM.

[![中文文档](https://img.shields.io/badge/文档-中文-blue?style=flat-square)](docs/README.zh-CN.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-green?style=flat-square)](#license)

## What is this?

[OpenClaw](https://github.com/openclaw/openclaw) is an open-source personal AI assistant you run on your own devices.

**openclaw-orbstack** is a **deployment tool** for macOS. It provisions an OrbStack Ubuntu VM, installs OpenClaw and its Docker sandboxes inside it, wires up the setup wizard, and drops a set of convenient `openclaw-*` commands into your Mac's `PATH` so you can drive the whole thing without ever `ssh`-ing into the VM.

The architecture below (a Gateway process plus Docker sandboxes) is [OpenClaw's official design](https://docs.openclaw.ai/install) — we don't invent it. We package it into a one-click installer with Mac-native convenience commands and a self-healing update flow.

**Why run it in a VM?**

- The Docker sandbox layer is the boundary that keeps the AI's tool execution away from your Mac's files.
- The VM keeps OpenClaw's Node.js Gateway, systemd service, and container runtime fully isolated from your host system.
- Updates, rebuilds, and a full uninstall stay contained — nothing is scattered across your Mac.

## Architecture

```
☁️  Cloud AI (Anthropic / OpenAI / Google)   ← the AI brain runs HERE
     ↑ API calls
     │
Mac ─┼──────────────────────────────────────────────────
     │   (~/bin/openclaw-* commands drive everything below)
     │
└── OrbStack
    └── Ubuntu VM (openclaw-vm)
        │
        ├── Gateway process (Node.js, systemd — NOT in Docker)
        │   - Receives chat messages
        │   - Calls the cloud AI APIs
        │   - Dispatches tool execution to the sandboxes
        │
        └── Docker (two sandbox containers)
            ├── sandbox-common (code execution)  ← sandbox.docker config
            └── sandbox-browser (Chromium)       ← sandbox.browser config
```

**Key concepts**

- ☁️ The AI brain runs in the **cloud** (Anthropic / OpenAI / Google servers) — the VM never runs a model locally.
- 🔧 Sandboxes are the AI's "hands": they only execute tools, they don't run the model.
- 📦 There are only **two** sandboxes — code execution and browser.
- 🛡️ Docker is the only isolation protecting your Mac's files, so keep the sandbox enabled.

## Prerequisites

- macOS 12.3 or newer
- [OrbStack](https://orbstack.dev) installed and running

## Installation

```bash
git clone https://github.com/aaajiao/openclaw-orbstack.git
cd openclaw-orbstack
bash openclaw-orbstack-setup.sh
```

The installer starts with a language prompt (English / 中文), then runs an 8-step flow automatically:

> Check OrbStack → Create Ubuntu VM → Install Docker → Install Node.js 24 → Install OpenClaw (npm, source-build fallback) → Build sandbox images → Configuration wizard → Service + Mac commands

OpenClaw is installed from the **prebuilt npm package** by default. On a *first* install, if the npm package fails, the installer falls back to a source build so you're never left without a working Gateway.

To skip the language prompt, set it via environment variable:

```bash
OPENCLAW_LANG=en    bash openclaw-orbstack-setup.sh   # English
OPENCLAW_LANG=zh-CN bash openclaw-orbstack-setup.sh   # 中文
```

After install, `~/bin` is added to your `PATH` — **open a new terminal window** and the `openclaw-*` commands are ready.

**Web console:** `http://openclaw-vm.orb.local:18789`

## Updating

`openclaw-update` is the **one** update command. It updates the wrapper (this repo, regenerating the `~/bin/openclaw-*` commands) first, then installs the wrapper-aligned OpenClaw version into the VM — single command, old muscle memory works again.

```bash
openclaw-update                     # Follow your current channel (see table below)
openclaw-update --pre               # Switch to the beta channel (sticky)
openclaw-update --stable            # Switch back to the stable channel (sticky)
openclaw-update --version=<tag>     # Pin wrapper+OpenClaw to a specific tag (rollback allowed)
openclaw-update --sandbox           # Also rebuild the sandbox Docker images
openclaw-update --force             # Force a rebuild / allow a downgrade
```

| Flag | Wrapper channel | Notes |
|------|------------------|-------|
| *(default)* | Follows your **current** channel | Branch checkout → `git pull` (interim, see note below); tag on stable → latest stable tag; tag on beta → newest tag incl. pre-releases |
| `--pre` | **Beta** channel, sticky | Moves to the newest tag including validated pre-releases; stays there until `--stable` |
| `--stable` | **Stable** channel, sticky | Moves back to the latest stable tag; the VM-side OpenClaw downgrade this often implies still needs `--force` (or wait for the next stable) |
| `--version=<tag>` | **Pinned** | If a wrapper tag `<tag>` exists, pins wrapper **and** OpenClaw together — a later plain `openclaw-update` keeps the pin and says so; `--pre`/`--stable` resumes following a channel. If no matching wrapper tag exists, it pins only the OpenClaw version (unchanged legacy behavior) |

- **Won't silently downgrade OpenClaw.** If the target is *older* than what's already built in the VM, it refuses unless you pass `--force` (the `--version=` pin path is exempt).
- **npm-based and honest.** It installs the prebuilt npm package, then verifies the Gateway actually boots. If the package is incomplete it stops and tells you (with a log hint) rather than silently dropping into a long, screen-garbling source build.
- **Self-healing.** It auto-detects and repairs stale installs — for example, migrating an old system-level service to the current user-level service, or recreating a missing plugin directory.
- **Keeps the git checkout in sync.** The `~/openclaw` checkout is always moved to the target tag, because the sandbox Docker images are built from that repo.

> **Note:** `refresh-mac-commands.sh` still auto-`git pull`s the wrapper repo's `main` branch when your checkout is on a branch, so branch users stay current automatically between runs. Pinning a tag puts the repo on a detached HEAD, which the auto-pull respects — it won't undo your pin. The full cutover (removing the auto-pull block entirely, since `openclaw-update` now handles the wrapper) is deferred to the first v2026.7.1 stable release.

### Versioning & release model

The wrapper version always **mirrors a real upstream OpenClaw version** — we never invent version numbers.

| Upstream OpenClaw | Wrapper release | Get it with |
|-------------------|-----------------|-------------|
| Stable release | Published as **Latest** | `openclaw-update --stable` |
| Validated / tested **beta** | Published as a **pre-release** | `openclaw-update --pre` |

Current state (illustrative — see the [GitHub Releases](https://github.com/aaajiao/openclaw-orbstack/releases) page for the live pair): wrapper stable is **v2026.6.11** (Latest); **v2026.7.1-beta.6** is available as a pre-release.

## Quick Start

```bash
# Open a new terminal so ~/bin is on PATH, then:

openclaw-status                        # Check service status
openclaw-logs                          # Follow live logs

# Telegram bot pairing
openclaw-telegram add <bot_token>      # Add a bot
openclaw-telegram approve <code>       # Approve with the pairing code

# WhatsApp login
openclaw-whatsapp

# Edit config
openclaw-config edit

# Use the official CLI (150+ commands)
openclaw --help
openclaw status
openclaw channels list
openclaw doctor
```

## Mac Commands

All 15 commands are generated into `~/bin` from a single command table in `scripts/refresh-mac-commands.sh`. Re-run `openclaw-update` (or `bash scripts/refresh-mac-commands.sh`) to regenerate them. Five are deprecated compatibility aliases — they still work today but print a one-line `[deprecated]` notice on stderr pointing at their native replacement; removal is deferred to a future stable release.

| Command | Function |
|---------|----------|
| `openclaw` | Official CLI passthrough (all upstream commands) — prefer this over the deprecated aliases below |
| `openclaw-status` | Gateway service status |
| `openclaw-logs` | Follow live Gateway logs |
| `openclaw-restart` | Restart the Gateway service |
| `openclaw-start` / `openclaw-stop` | *Deprecated alias, still works* → `openclaw gateway start` / `openclaw gateway stop` |
| `openclaw-shell` | Open a shell inside the VM |
| `openclaw-doctor` | *Deprecated alias, still works* → `openclaw doctor` |
| `openclaw-config` | Manage config (`edit` / `show` / `backup`) |
| `openclaw-telegram` | *Deprecated alias, still works* → `openclaw channels add --channel telegram --token <token>` / `openclaw pairing approve telegram <code>` |
| `openclaw-whatsapp` | *Deprecated alias, still works* → `openclaw channels login --channel whatsapp` |
| `openclaw-codex-login` | Bind a ChatGPT subscription via Codex device-code login (optional) |
| `openclaw-update` | **Update everything: wrapper + OpenClaw** (channels: `--pre`/`--stable`; also `--version=<tag>`, `--sandbox`, `--force`) |
| `openclaw-sandbox-rebuild` | Rebuild the sandbox Docker images |
| `openclaw-uninstall` | Clean uninstall |

Full command reference: [docs/commands.md](docs/commands.md)

## Configuration

Config file (inside the VM): `~/.openclaw/openclaw.json`

```bash
openclaw-config edit     # Edit
openclaw-config show     # View
openclaw-config backup   # Backup
```

Detailed configuration guide: https://docs.openclaw.ai/gateway/configuration

## Troubleshooting

```bash
openclaw-status        # Service status
openclaw-logs          # View logs
openclaw doctor        # Run diagnostics
openclaw-shell         # Enter the VM for debugging
```

Full troubleshooting guide: [docs/troubleshooting.md](docs/troubleshooting.md)

### Common Issues

| Issue | Solution |
|-------|----------|
| Bonjour hostname conflict | Re-run the setup script, or add the env var manually |
| Port 18789 in use | `openclaw-restart`, or `openclaw-update` |
| Memory directory error | `mkdir -p ~/.openclaw/memory` (see below) |
| Memory search not working | Add an OpenAI / Google key to the agent's `auth-profiles.json` |
| Wrapper commands out of date | `openclaw-update` |

### Memory Directory Issue

If you see an `EISDIR: illegal operation on a directory` error, create the memory index directory manually:

```bash
openclaw-shell
mkdir -p ~/.openclaw/memory
chmod 755 ~/.openclaw/memory
exit
openclaw-restart
```

### Backup & Restore

```bash
orb export openclaw-vm ~/Desktop/backup.tar.zst    # Full VM snapshot
orb import -n openclaw-vm ~/Desktop/backup.tar.zst  # Restore from a snapshot
```

See [docs/troubleshooting.md](docs/troubleshooting.md) for more.

## Documentation

The deep-dive guides under `docs/` are currently written in Chinese. This README covers the English essentials — install, the update model, and commands. For the full English reference, see the upstream OpenClaw documentation at https://docs.openclaw.ai. `docs/README.zh-CN.md` is the Chinese README for this project.

| Document | Content |
|----------|---------|
| [docs/README.zh-CN.md](docs/README.zh-CN.md) | 中文文档 |
| [docs/commands.md](docs/commands.md) | CLI & Mac command reference |
| [docs/architecture.md](docs/architecture.md) | Architecture details |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Troubleshooting (OrbStack-specific) |
| [docs/development.md](docs/development.md) | Development guide |

## License

MIT
