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

There are **two** update commands, and they **compose**. `openclaw-selfupdate` picks your *channel* — which wrapper release you're on (stable, or a validated beta via `--pre`). `openclaw-update` then installs the OpenClaw version that wrapper is aligned with. You normally run them in sequence: select the channel, then apply it to the VM.

| Command | Updates | Runs on | Role |
|---------|---------|---------|------|
| `openclaw-selfupdate` | **This wrapper** (openclaw-orbstack — the `openclaw-*` commands & scripts) | Your Mac host | Picks the **channel** — moves the wrapper to a stable tag, a validated beta (`--pre`), or a pinned/rolled-back tag |
| `openclaw-update` | **OpenClaw itself** (the app inside the VM) | The VM | Installs the OpenClaw version the **current wrapper is aligned with** |

`openclaw-selfupdate` doesn't touch the VM directly — but the wrapper tag it lands on **determines which OpenClaw version the next `openclaw-update` installs**. That's why they're run together, not in isolation.

### `openclaw-update` — install OpenClaw in the VM

```bash
openclaw-update                     # Install the OpenClaw version this wrapper is aligned with
openclaw-update --version=<tag>     # Install / roll back to a specific OpenClaw version
openclaw-update --sandbox           # Also rebuild the sandbox Docker images
openclaw-update --force             # Force a rebuild even if already current
```

- **Follows the wrapper's version.** By default it installs the OpenClaw release this wrapper is *aligned with* — the wrapper's `VERSION`, which mirrors a real upstream OpenClaw version — not simply "latest upstream stable". So after `openclaw-selfupdate --pre` moves you onto a beta wrapper, a plain `openclaw-update` installs the matching OpenClaw beta.
- **Won't silently downgrade.** If the wrapper-aligned target is *older* than what's already built in the VM, it refuses unless you pass `--force`. To roll back on purpose, use `--version=<tag>` (that path is exempt from the guard).
- **npm-based and honest.** It installs the prebuilt npm package, then verifies the Gateway actually boots. If the package is incomplete it stops and tells you (with a log hint) rather than silently dropping into a long, screen-garbling source build.
- **Self-healing.** It auto-detects and repairs stale installs — for example, migrating an old system-level service to the current user-level service, or recreating a missing plugin directory.
- **Keeps the git checkout in sync.** The `~/openclaw` checkout is always moved to the target tag, because the sandbox Docker images are built from that repo.

### `openclaw-selfupdate` — pick the channel (update this wrapper)

```bash
openclaw-selfupdate                 # Move to the latest STABLE wrapper release
openclaw-selfupdate --pre           # Move to the newest release, including validated pre-releases (beta/rc/alpha)
openclaw-selfupdate --version=<tag> # Pin to a specific wrapper tag — e.g. v2026.6.6 (allows rollback)
```

- **Release-pinned channel selector.** By default it checks out the latest **stable** tag. `--pre` moves you to the newest tag overall (including validated betas). `--version=` pins any tag exactly, so you can roll back.
- **Never downgrades on the default or `--pre` path.** If your checkout already includes the target, it's a no-op. Only an explicit `--version=` can move you to an older tag.
- **Mac-only, but not unrelated to OpenClaw.** It operates entirely on your local repo clone and regenerates the `~/bin/openclaw-*` commands. It never touches the VM itself — yet the tag you land on **selects the channel that the next `openclaw-update` follows**.

### Composed workflows

```bash
# Move onto the beta line — the VM's OpenClaw goes to the matching beta:
openclaw-selfupdate --pre
openclaw-update

# Stay on / return to stable:
openclaw-selfupdate
openclaw-update
```

> **Note:** `openclaw-selfupdate` is available now as an **opt-in** command. `refresh-mac-commands.sh` also still auto-`git pull`s the wrapper repo's `main` branch when your checkout is on a branch, so branch users stay current automatically. Pinning a tag with `openclaw-selfupdate` puts the repo on a detached HEAD, which the auto-pull respects — it won't undo your pin. The full cutover to `openclaw-selfupdate` as the *sole* wrapper-delivery path (removing the auto-pull block entirely) is deferred to the first v2026.7.1 stable release.

### Versioning & release model

The wrapper version always **mirrors a real upstream OpenClaw version** — we never invent version numbers.

| Upstream OpenClaw | Wrapper release | Get it with |
|-------------------|-----------------|-------------|
| Stable release | Published as **Latest** | `openclaw-selfupdate` |
| Validated / tested **beta** | Published as a **pre-release** | `openclaw-selfupdate --pre` |

Current state (illustrative — see the [GitHub Releases](https://github.com/aaajiao/openclaw-orbstack/releases) page for the live pair): wrapper stable is **v2026.6.11** (Latest); **v2026.7.1-beta.5** is available as a pre-release.

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

All 16 commands are generated into `~/bin` from a single command table in `scripts/refresh-mac-commands.sh`. Re-run `openclaw-selfupdate` (or `bash scripts/refresh-mac-commands.sh`) to regenerate them. Five are deprecated compatibility aliases — they still work today but print a one-line `[deprecated]` notice on stderr pointing at their native replacement; removal is deferred to a future stable release.

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
| `openclaw-update` | **Update OpenClaw in the VM** (`--version=<tag>`, `--sandbox`, `--force`) |
| `openclaw-selfupdate` | **Update this wrapper** (`--pre`, `--version=<tag>`) |
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
| Wrapper commands out of date | `openclaw-selfupdate` |

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
