# OpenClaw OrbStack

One-click [OpenClaw](https://github.com/openclaw/openclaw) deployment on macOS via OrbStack VM.

**[中文文档](docs/README.zh-CN.md)**

## What is this?

[OpenClaw](https://docs.openclaw.ai) is an open-source AI chatbot platform that connects to 25+ messaging channels (Telegram, WhatsApp, Discord, Slack, etc.) and supports all major AI providers (Anthropic, OpenAI, Google, etc.).

This project (**openclaw-orbstack**) is a **deployment tool** — it automates the from-source build and OrbStack VM setup on macOS. The architecture below (Gateway process + Docker sandboxes) is [OpenClaw's official design](https://docs.openclaw.ai/install), not something we invented. We simply package it into a one-click installer with Mac convenience commands.

## Architecture

```
☁️  Cloud AI (Anthropic/OpenAI/Google)  ← AI brain runs HERE
     ↑ API calls
     │
Mac ─┼─────────────────────────────────────────────────
     │
└── OrbStack
    └── Ubuntu VM (openclaw-vm)
        │
        ├── Gateway process (orchestrator, NOT in Docker)
        │   - Receives chat messages
        │   - Calls cloud AI APIs
        │   - Dispatches tool execution to sandboxes
        │
        └── Docker (two sandbox containers)
            ├── sandbox-common (code execution)  ← sandbox.docker config
            └── sandbox-browser (browser)        ← sandbox.browser config
```

**Key Concepts**:
- ☁️ AI brain runs in the **cloud** (Anthropic/OpenAI/Google servers)
- 🔧 Sandboxes are AI's "hands" — they only execute tools, not run AI
- 📦 Only **TWO** sandboxes: code execution + browser

**Benefits**:
- ✅ Follows OpenClaw's official recommended architecture
- ✅ Gateway can properly manage sandbox containers
- ✅ VM isolation layer protects your Mac

## Prerequisites

- macOS 12.3+
- [OrbStack](https://orbstack.dev) installed

## Installation

```bash
git clone https://github.com/aaajiao/openclaw-orbstack.git
cd openclaw-orbstack
bash openclaw-orbstack-setup.sh
```

The script starts with a language selection prompt (English / 中文), then automatically: Creates VM → Installs Docker/Node.js → Builds OpenClaw → Runs setup wizard → Starts service

To skip the prompt, set the language via environment variable:

```bash
OPENCLAW_LANG=en bash openclaw-orbstack-setup.sh      # English
OPENCLAW_LANG=zh-CN bash openclaw-orbstack-setup.sh   # Chinese
```

## Access

Web Console: `http://openclaw-vm.orb.local:18789`

## Quick Start

```bash
# Add ~/bin to PATH (use ~/.bashrc for bash, ~/.config/fish/config.fish for fish)
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc

# Check service status
openclaw-status

# View logs
openclaw-logs

# Telegram Bot pairing
openclaw-telegram add <bot_token>      # Add Bot
openclaw-telegram approve <code>       # Approve with code

# WhatsApp login
openclaw-whatsapp

# Edit config
openclaw-config edit

# Use official CLI (150+ commands)
openclaw --help
openclaw status
openclaw channels list
openclaw doctor
```

## Mac Commands

| Command | Function |
|---------|----------|
| `openclaw` | CLI passthrough (all official commands) |
| `openclaw-telegram` | Telegram management (add/approve) |
| `openclaw-whatsapp` | WhatsApp login |
| `openclaw-config` | Config management |
| `openclaw-status` | Service status |
| `openclaw-logs` | Live logs |
| `openclaw-restart` | Restart service |
| `openclaw-stop/start` | Stop/start service |
| `openclaw-shell` | Enter VM terminal |
| `openclaw-doctor` | Run diagnostics |
| `openclaw-update` | Update app (`--sandbox` to rebuild images) |
| `openclaw-sandbox-rebuild` | Rebuild sandbox Docker images |

Full command reference: [docs/commands.md](docs/commands.md)

## Configuration

Config file: `~/.openclaw/openclaw.json` (inside VM)

```bash
openclaw-config edit     # Edit
openclaw-config show     # View
openclaw-config backup   # Backup
```

Detailed configuration guide: [docs/configuration-guide.md](docs/configuration-guide.md)

## Troubleshooting

```bash
openclaw-status        # Service status
openclaw-logs          # View logs
openclaw doctor        # Run diagnostics
openclaw-shell         # Enter VM for debugging
```

Full troubleshooting guide: [docs/troubleshooting.md](docs/troubleshooting.md)

### Upgrading Existing Installations

```bash
openclaw-update
```

This auto-detects and repairs outdated configurations (e.g. migrating from system-level to user-level service).

> **For users upgrading from before v2026.3.1:**
> Run this **one last time** to switch to the new auto-updating wrapper system:
>
> ```bash
> cd openclaw-orbstack && git pull && bash scripts/refresh-mac-commands.sh
> ```
>
> After this, `openclaw-update` will automatically pull the latest orchestrator scripts before each update — **no more manual `git pull && refresh` needed**.

### Common Issues

| Issue | Solution |
|-------|----------|
| Bonjour hostname conflict | Re-run setup script or manually add env var |
| Port 18789 in use | `openclaw-restart` or `openclaw-update` |
| Memory directory error | `mkdir -p ~/.openclaw/memory` |
| Memory search not working | Add OpenAI/Google key to agent auth-profiles.json |

## Documentation

| Document | Content |
|----------|---------|
| [docs/README.zh-CN.md](docs/README.zh-CN.md) | Chinese documentation |
| [docs/commands.md](docs/commands.md) | CLI command reference |
| [docs/architecture.md](docs/architecture.md) | Architecture details |
| [docs/configuration-guide.md](docs/configuration-guide.md) | Configuration guide |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Troubleshooting guide |
| [docs/sandbox.md](docs/sandbox.md) | Sandbox security |
| [docs/skills.md](docs/skills.md) | Skills guide |
| [docs/voice-tts.md](docs/voice-tts.md) | Voice features |

## License

MIT
