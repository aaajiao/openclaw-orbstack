# CLAUDE.md - Project Guide for Claude Code

**Project:** OpenClaw OrbStack — one-click OpenClaw AI chatbot deployment on macOS via OrbStack VM.
**Version:** v2026.2.26 | **License:** MIT

## Architecture

```
☁️  Cloud AI (Anthropic/OpenAI/Google)  ← AI brain
     ↑ API calls
Mac ──────────────────────────────────────
└── OrbStack
    └── Ubuntu VM (openclaw-vm)
        ├── Gateway (Node.js, systemd)    ← orchestrator, NOT in Docker
        └── Docker
            ├── sandbox-common            ← code execution
            └── sandbox-browser           ← Chromium
```

Gateway runs directly on VM. Docker containers are the only isolation protecting Mac files (VM has `/mnt/mac` access).

## Project Structure

- `openclaw-orbstack-setup.sh` — Main entry point (8-step installer, ~850 lines)
- `lang/en.sh`, `lang/zh-CN.sh` — i18n message strings (`$MSG_*` variables)
- `templates/openclaw.json.example` — Full JSON5 config template (reference only)
- `scripts/refresh-mac-commands.sh` — Regenerate `~/bin/openclaw-*` wrappers
- `docs/` — Architecture, commands, config guide, troubleshooting, sandbox, dev guide
- `local/` — **Developer's actual runtime config (gitignored)**, see below
- `VERSION` — openclaw-orbstack project version (not OpenClaw version)

## local/ Directory (gitignored)

This directory contains the developer's **actual runtime configuration** for their VM instance. Files here are gitignored but serve as the source of truth for the running system.

| File | Purpose | Syncs To (in VM) |
|------|---------|------------------|
| `openclaw.json` | Full Gateway config (agents, models, sandbox, channels, etc.) | `~/.openclaw/openclaw.json` |
| `.env` | Secrets (API keys, bot tokens, Gateway auth token) | `~/.openclaw/.env` |

### Relationship: local/ vs templates/

| Directory | Role | When to Edit |
|-----------|------|--------------|
| `templates/openclaw.json.example` | Reference template with comments | When adding new config options to document |
| `local/openclaw.json` | Actual working config | When tuning your own setup |

### Sync Workflow

```bash
# Mac → VM: Push config changes
cat local/openclaw.json | orb -m openclaw-vm tee ~/.openclaw/openclaw.json > /dev/null
cat local/.env | orb -m openclaw-vm tee ~/.openclaw/.env > /dev/null

# VM → Mac: Pull config changes (after openclaw configure or manual edits)
orb -m openclaw-vm cat ~/.openclaw/openclaw.json > local/openclaw.json
orb -m openclaw-vm cat ~/.openclaw/.env > local/.env

# Apply changes
openclaw gateway restart
```

### Key Config Sections in local/openclaw.json

| Section | Purpose |
|---------|---------|
| `auth.profiles` | Provider auth metadata (actual keys in `auth-profiles.json` on VM) |
| `agents.defaults.model` | Primary/fallback models for main agent |
| `agents.defaults.models` | Model catalog/allowlist, custom providers via `models.providers` |
| `agents.defaults.memorySearch` | Vector memory index settings (SQLite, embedding provider, hybrid search) |
| `agents.defaults.sandbox` | Docker sandbox config (image, limits, env vars) |
| `channels.telegram` | Telegram bot settings (token, groups, policies) |
| `session` | DM scope (per-peer, per-channel-peer, etc.), auto-reset |
| `hooks` | External event triggers (e.g., GitHub webhook → AI action) |
| `cron` | Scheduled tasks (enabled, maxConcurrentRuns, sessionRetention) |
| `gateway` | Port, auth, Tailscale, reload mode settings |
| `env` | Static vars + shellEnv (login shell import) |
| `skills.entries` | Skill-specific API keys |
| `plugins` | Plugin system (requires restart) |
| `$include` | Multi-file config support (single file or array, nested up to 10 levels) |

### memorySearch Config

Memory search creates a SQLite vector index (`~/.openclaw/memory/<agentId>.sqlite`) for semantic search over memory files and session history.

```json
"memorySearch": {
  "enabled": true,
  "fallback": "openai",                    // Fallback if primary fails
  "sources": ["memory", "sessions"],       // What to index
  "experimental": { "sessionMemory": true }, // Index session transcripts
  "sync": {
    "watch": true,                         // Watch for file changes
    "sessions": {
      "deltaBytes": 50000,                 // Sync after 50KB changes
      "deltaMessages": 30                  // Or after 30 messages
    }
  },
  "cache": { "enabled": true, "maxEntries": 50000 },
  "query": {
    "hybrid": {                            // BM25 + vector search
      "enabled": true,
      "vectorWeight": 0.7,
      "textWeight": 0.3
    }
  },
  "remote": {
    "batch": { "enabled": true, "concurrency": 2 }  // Cheaper batch API
  }
}
```

**Provider selection** (when `provider` is omitted): OpenClaw auto-selects `local` → `openai` → `gemini` based on available API keys. Valid explicit values: `"auto"` | `"openai"` | `"gemini"` | `"local"`.

**Full documentation**: See [docs/configuration-guide.md](docs/configuration-guide.md) for complete configuration guide.

## Key Facts

| Item | Value |
|------|-------|
| VM name | `openclaw-vm` |
| Gateway port | `18789` |
| Web console | `http://openclaw-vm.orb.local:18789` |
| Config (in VM) | `~/.openclaw/openclaw.json` |
| Secrets (in VM) | `~/.openclaw/.env` |
| Node.js | 22.x LTS |
| Service | `systemctl --user` (`openclaw-gateway.service`) |
| Gateway cmd | `node dist/entry.js gateway --port 18789` |

## Build / Test / Run

```bash
# Install (interactive language selection)
bash openclaw-orbstack-setup.sh

# Skip language prompt
OPENCLAW_LANG=en bash openclaw-orbstack-setup.sh

# Validate
bash -n openclaw-orbstack-setup.sh          # syntax check
shellcheck openclaw-orbstack-setup.sh       # lint

# Clean reinstall
orb delete openclaw-vm && OPENCLAW_LANG=en bash openclaw-orbstack-setup.sh
```

No automated test suite. Validation is syntax checks + shellcheck + manual testing.

## Coding Conventions

### Bash
- Always `set -e` at top of scripts
- Constants: `UPPER_SNAKE_CASE`
- Functions: `lowercase` for utils, `snake_case` for complex logic
- Quoted heredoc delimiters (`'EOF'`) to prevent expansion; unquoted for expansion
- User-facing text: use `$MSG_*` variables from `lang/*.sh`, never hardcode
- Code comments: English

### JSON Configuration
- Format: JSON5 (comments and trailing commas allowed)
- Indentation: 2 spaces
- Dynamic edits: use `jq`, never sed for JSON/YAML

### i18n
- All user-facing text goes through `lang/*.sh` message strings
- `OPENCLAW_LANG` env var selects language (`en` or `zh-CN`)
- Falls back to English if language file missing

## Anti-Patterns (avoid these)

| Don't | Why | Do Instead |
|-------|-----|------------|
| `sandbox.mode: "off"` | AI accesses Mac via `/mnt/mac` | Keep `mode: "all"` |
| API keys in top-level `env: {}` | Sandbox doesn't inherit Gateway env | Use `sandbox.docker.env` |
| `TELEGRAM_BOT_TOKEN` in sandbox | Reserved by Gateway | Use `TG_BOT_TOKEN` |
| `DISCORD_BOT_TOKEN` in sandbox | Reserved by Gateway | Use `DISCORD_TOKEN` |
| Missing `set -e` | Errors silently continue | Always `set -e` |
| sed for YAML/JSON edits | Silently fails on complex structures | Use `jq` or Python |

## Environment Variable Scopes

Three independent scopes — they do NOT inherit from each other:

| Scope | Config Location | Reaches |
|-------|----------------|---------|
| Gateway | Top-level `env: {}` | Gateway process only |
| Code sandbox | `sandbox.docker.env` | Code execution container |
| Browser sandbox | `sandbox.browser.env` | Browser container |

## Secrets Management (.env)

- `~/.openclaw/.env` stores sensitive values (API keys, bot tokens, Bonjour settings)
- Generated **automatically** during Step 7 (after `openclaw onboard`) by a Python3 extraction script
- Config file (`openclaw.json`) references secrets via `${VAR}` syntax (e.g., `"token": "${TG_BOT_TOKEN}"`)
- Gateway reads `.env` at startup via systemd `EnvironmentFile`
- `openclaw-update` only creates a minimal `.env` (Bonjour vars) if the file is missing — it does NOT re-extract secrets
- File permissions: `chmod 600` (owner-only read/write)

## Reference Docs

| Topic | URL |
|-------|-----|
| OpenClaw getting started | https://docs.openclaw.ai/start/getting-started |
| OpenClaw config | https://docs.openclaw.ai/gateway/configuration |
| OpenClaw model providers | https://docs.openclaw.ai/concepts/model-providers |
| OpenClaw channels | https://docs.openclaw.ai/channels |
| OpenClaw install methods | https://docs.openclaw.ai/install |
| OpenClaw env vars | https://docs.openclaw.ai/help/environment |
| OpenCode Zen models | https://opencode.ai/docs/zen/ |

## Git

```bash
# Push with gh token
git push https://aaajiao:$(gh auth token)@github.com/aaajiao/openclaw-orbstack.git main
```

## CI

GitHub Actions runs shellcheck on shell scripts (`.github/workflows/shellcheck.yml`).
