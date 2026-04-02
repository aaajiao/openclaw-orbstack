# CLAUDE.md - Project Guide for Claude Code

**Project:** OpenClaw OrbStack — one-click OpenClaw AI chatbot deployment on macOS via OrbStack VM.
**Version:** v2026.4.2 | **License:** MIT

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

**IMPORTANT: Claude Code runs on the Mac host, NOT inside the VM.**
- NEVER run commands inside the VM, access VM files, or diagnose VM processes
- NEVER use `orb`, `ssh`, or any tool to execute inside `openclaw-vm` unless user explicitly instructs
- When VM state is needed (logs, service status, sandbox output), ask the user to provide it
- All file edits, searches, and validations happen on the Mac filesystem in this repo
- This project develops *scripts that manage* the VM — it does not run inside it

## Project Structure

- `openclaw-orbstack-setup.sh` — Main entry point (8-step installer, ~750 lines)
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

Config section reference is in `memory/config.md`. Detailed config docs: https://docs.openclaw.ai/gateway/configuration

## Persistent Knowledge

Architecture decisions, config structure, feature status, and operational knowledge are tracked in `memory/MEMORY.md`. Check it when you need context beyond what's in this file.

## Key Facts

| Item | Value |
|------|-------|
| VM name | `openclaw-vm` |
| Gateway port | `18789` |
| Web console | `http://openclaw-vm.orb.local:18789` |
| Config (in VM) | `~/.openclaw/openclaw.json` |
| Secrets (in VM) | `~/.openclaw/.env` |
| Node.js | 24.x LTS |
| Service | `systemctl --user` (`openclaw-gateway.service`) |
| Gateway cmd | `node dist/entry.js gateway --port 18789` |

## Build / Test / Run

```bash
# Install (interactive language selection)
bash openclaw-orbstack-setup.sh

# Skip language prompt
OPENCLAW_LANG=en bash openclaw-orbstack-setup.sh

# Validate (Claude can run these)
bash -n openclaw-orbstack-setup.sh          # syntax check
shellcheck openclaw-orbstack-setup.sh       # lint
```

No automated test suite. Validation is syntax checks + shellcheck + manual testing.

### Install Strategy

Both the installer and updater use the same two-tier approach:

1. **Primary**: `npm install -g openclaw@<version>` (prebuilt npm package — fast, reliable)
2. **Fallback**: `pnpm install && pnpm build && pnpm ui:build && sudo npm install -g .` (source build — only if npm registry fails)

The git checkout (`~/openclaw`) is always kept at the target tag regardless of install method, because sandbox Docker images are built from the repo's Dockerfiles.

A `.build-version` marker (`~/.openclaw/.build-version`) tracks successful installs. `openclaw-update` checks this marker to avoid skipping a version whose previous install attempt failed.

## Verification Checklist

Before declaring a task done, verify all applicable items:

| Task Type | Verification |
|-----------|-------------|
| Edit `.sh` files | `bash -n <file>` + `shellcheck <file>` pass |
| Edit JSON/JSON5 config | Valid syntax (visual check for JSON5, `jq .` for strict JSON) |
| Edit `templates/openclaw.json.example` | New options match upstream docs structure |
| Add/change `$MSG_*` strings | Both `lang/en.sh` and `lang/zh-CN.sh` updated |
| Upstream sync | `VERSION` + `CLAUDE.md` version header both updated |
| Any commit | `bash -n openclaw-orbstack-setup.sh` passes |

## Quick Reference

| Task | Steps |
|------|-------|
| Edit shell script | Edit file → hook auto-runs `bash -n` + `shellcheck` |
| Edit JSON config | Check upstream docs → Edit → hook auto-runs `jq .` (strict JSON) |
| Sync upstream | `/sync-upstream` → review → approve → commit → user tests → push |
| Add i18n string | Add `$MSG_*` to both `lang/en.sh` and `lang/zh-CN.sh` (hook reminds) |
| Need VM state | Ask user to provide it — never access VM directly |

## Coding Conventions

Language-specific rules are in `.claude/rules/` (auto-applied by file type).

### i18n
- All user-facing text goes through `lang/*.sh` message strings
- `OPENCLAW_LANG` env var selects language (`en` or `zh-CN`)
- Falls back to English if language file missing

### Execution Style
- Prefer action over extended planning — when the task is clear, execute directly
- Don't create sub-teams or toggle plan mode repeatedly for straightforward tasks

## Anti-Patterns (avoid these)

| Don't | Why | Do Instead |
|-------|-----|------------|
| `sandbox.mode: "off"` | AI accesses Mac via `/mnt/mac` | Keep `mode: "all"` |
| API keys in top-level `env: {}` | Sandbox doesn't inherit Gateway env | Use `sandbox.docker.env` |
| `TELEGRAM_BOT_TOKEN` in sandbox | Reserved by Gateway | Use `TG_BOT_TOKEN` |
| `DISCORD_BOT_TOKEN` in sandbox | Reserved by Gateway | Use `DISCORD_TOKEN` |
| Missing `set -e` | Errors silently continue | Always `set -e` |
| sed for YAML/JSON edits | Silently fails on complex structures | Use `jq` or Python |

## Reference Docs

| Topic | URL |
|-------|-----|
| OpenClaw GitHub (upstream) | https://github.com/openclaw/openclaw |
| OpenClaw getting started | https://docs.openclaw.ai/start/getting-started |
| OpenClaw config | https://docs.openclaw.ai/gateway/configuration |
| OpenClaw model providers | https://docs.openclaw.ai/concepts/model-providers |
| OpenClaw channels | https://docs.openclaw.ai/channels |
| OpenClaw install methods | https://docs.openclaw.ai/install |
| OpenClaw env vars | https://docs.openclaw.ai/help/environment |
| OpenCode Zen models | https://opencode.ai/docs/zen/ |

## Git

```bash
git push origin main
```

## CI

GitHub Actions runs shellcheck on shell scripts (`.github/workflows/shellcheck.yml`).

## Release Workflow

1. Use `/sync-upstream` to check for new upstream OpenClaw releases and apply changes
2. Implement changes and commit
3. Let user test locally before proceeding
4. Only after user confirms: push, tag, and create GitHub release

Never push or create releases without explicit user approval after testing.

## Config Editing Rules

Detailed rules in `.claude/rules/json-config.md` (auto-applied for JSON/JSON5 files).
When unsure about a field's parent key, check `memory/config.md`.

## Removal / Deletion Rules

- Before claiming a CLI command, config option, or feature doesn't exist, verify against at least two sources (official docs + code/community search)
- Never remove functionality based on a single source — ask user to test if you can't verify yourself
- When editing docs that reference upstream features, WebFetch the upstream docs first
