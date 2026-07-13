# CLAUDE.md - Project Guide for Claude Code

**Project:** OpenClaw OrbStack — one-click OpenClaw AI chatbot deployment on macOS via OrbStack VM.
**Version:** v2026.7.1 | **License:** MIT

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
            │   └── /workspace/           ← persistent volume, agent-managed deps
            └── sandbox-browser           ← Chromium
```

Gateway runs directly on VM. Docker containers are the only isolation protecting Mac files (VM has `/mnt/mac` access).

### Three-Layer Maintenance Model

| Layer | Owner | How | Can we modify? |
|-------|-------|-----|----------------|
| Docker images | Upstream OpenClaw | Follow upstream updates, don't touch | No |
| VM (`openclaw-vm`) | Us (minimal intervention) | `local/weekly-maintenance.sh` + installer/updater scripts | Yes, but keep minimal |
| `/workspace/` in sandbox | AI agent (self-managed) | Rebuild script restores deps after container recreation | Agent-autonomous |

Each layer is responsible only for itself. Diagnose and fix issues at the layer where they occur.

The sandbox Dockerfile is upstream-controlled, so custom dependencies (bun, pnpm, etc.) are installed at runtime into `/workspace/` (persistent volume). A rebuild script can restore everything after container recreation. This is the optimal approach without forking the upstream image.

**IMPORTANT: Claude Code runs on the Mac host, NOT inside the VM.**
- NEVER run commands inside the VM, access VM files, or diagnose VM processes
- NEVER use `orb`, `ssh`, or any tool to execute inside `openclaw-vm` unless user explicitly instructs
- When VM state is needed (logs, service status, sandbox output), ask the user to provide it
- All file edits, searches, and validations happen on the Mac filesystem in this repo
- This project develops *scripts that manage* the VM — it does not run inside it

## Project Structure

- `openclaw-orbstack-setup.sh` — Main entry point (8-step installer, ~700 lines)
- `lang/en.sh`, `lang/zh-CN.sh` — i18n message strings (`$MSG_*` variables)
- `templates/openclaw.json.example` — Full JSON5 config template (reference only)
- `scripts/lib/common.sh` — Shared shell library (vm_exec, vm_log_tail, fmt_elapsed, language loading, PATH-append, gateway health poll, systemd drop-in writers, sandbox build+hash logic); sourced by the installer, `scripts/commands/_common.sh`, and the wrapper generator
- `scripts/refresh-mac-commands.sh` — Regenerate `~/bin/openclaw-*` wrappers from a command table
- `docs/` — Architecture, commands, config guide, troubleshooting, sandbox, dev guide
- `local/` — **Developer's actual runtime config (gitignored)**, see below
- `VERSION` — openclaw-orbstack project version (not OpenClaw version)

## local/ Directory (gitignored)

This directory contains the developer's **actual runtime configuration** for their VM instance. Files here are gitignored but serve as the source of truth for the running system.

| File | Purpose | Syncs To (in VM) |
|------|---------|------------------|
| `openclaw.json` | Full Gateway config (agents, models, sandbox, channels, etc.) | `~/.openclaw/openclaw.json` |
| `.env.local` | Secrets (API keys, bot tokens, Gateway auth token) | `~/.openclaw/.env` |

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
| Codex CLI auth (in VM) | `~/.codex/auth.json` — required for ChatGPT subscription path (PR #82117 fallback) |
| Node.js | 24.x LTS, **≥ 24.15.0** (hard floor since OpenClaw 2026.7.1 — SQLite WAL runtime guard, upstream #106065) |
| Service | `systemctl --user` (`openclaw-gateway.service`) |
| Gateway cmd | `node dist/index.js gateway --port 18789` |

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

**Installer** (`openclaw-orbstack-setup.sh`) — two-tier, for fresh installs:

1. **Primary**: `npm install -g openclaw@<version>` (prebuilt npm package — fast, reliable)
2. **Fallback**: `pnpm install && pnpm build && pnpm ui:build && sudo npm install -g .` (source build — only if the npm package fails on a first install, where there's no working openclaw to fall back on)

**Updater** (`openclaw-update`) — **npm-only** (source-build fallback removed 2026-06-10): if the npm install fails or the package is incomplete, it prints the log hint and aborts (`MSG_PKG_INSTALL_ABORT`, retry with `openclaw-update --force`) instead of dropping to a multi-minute, screen-garbling source build. Package completeness is checked against **`sudo npm root -g`** (root's prefix, `/usr/lib/node_modules`) to match where `sudo npm install -g` actually installs — a bare `npm root -g` resolves the *user's* workspace prefix (`~/.openclaw/workspace/.local/lib/node_modules`), where the package isn't, which previously forced a false-"incomplete" source build on every run.

The git checkout (`~/openclaw`) is always kept at the target tag regardless of install method, because sandbox Docker images are built from the repo's Dockerfiles.

A `.build-version` marker (`~/.openclaw/.build-version`) tracks successful installs. `openclaw-update` checks this marker to avoid skipping a version whose previous install attempt failed.

### Single-Command Update Model

`openclaw-update` is the **one** update command — see memory `[[wrapper-versioning-and-distribution]]`. It first updates **the wrapper itself** (this repo), regenerates `~/bin/openclaw-*`, then installs the resulting wrapper-aligned **OpenClaw** into the VM. Two internal stages, one user-facing command; a hidden `--wrapper-only` flag runs stage 1 alone (wrapper-only, no VM changes).

- **Channel inference (default, no flags)**: follows whatever channel the repo checkout is already on. Branch checkout → stage 1 `git pull`s the branch itself (re-execs when HEAD moved). Checkout pinned on a stable tag → follows the latest stable tag. Checkout on a beta tag → follows the newest tag including pre-releases.
- **`--pre`** switches to the beta channel and it's sticky (stays there across future plain runs until `--stable`).
- **`--stable`** switches back to the stable channel, sticky. Note the VM-side OpenClaw downgrade this often implies still needs `--force` (or wait for the next stable release).
- **`--version=<tag>`** pins. If a wrapper tag `<tag>` exists, it pins **wrapper and OpenClaw together** — a marker at `~/bin/.openclaw-pin` records this, so a later plain `openclaw-update` keeps the pin and says so instead of silently resuming a channel; `--pre`/`--stable` clears the marker and resumes following that channel. If no matching wrapper tag exists, it falls back to pinning only the OpenClaw version, same as legacy behavior.
- Stage 2 (OpenClaw) still refuses to downgrade without `--force` (`--version=` path exempt). Version compare translates the semver `-` prerelease separator to `~` before `sort -V` (not prerelease-aware on its own), so a stable release outranks its own prerelease.

**Cutover (completed 2026-07-14, v2026.7.1 stable sync)**: the generated `~/bin` shim no longer auto-`git pull`s — that block was removed from `refresh-mac-commands.sh`. `openclaw-update` stage 1 is the sole wrapper-delivery path: on a branch checkout it pulls the branch itself (and re-execs via `--after-self` when HEAD moved); on a detached HEAD it follows tags per the channel model above.

`~/bin/openclaw-*` wrappers are generated from a single command table in `scripts/refresh-mac-commands.sh` (10 commands total). The five former deprecated compatibility aliases (`openclaw-stop`, `openclaw-start`, `openclaw-doctor`, `openclaw-whatsapp`, `openclaw-telegram`) were removed outright on 2026-07-13 (user decision) — use the native commands instead (`openclaw gateway stop|start`, `openclaw doctor`, `openclaw channels login --channel whatsapp`, `openclaw channels add --channel telegram --token <token>` / `openclaw pairing approve telegram <code>`). Regenerating the commands also deletes stale alias files from `~/bin`.

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
| Sync upstream | `/sync-upstream` (scans stable + beta channels; beta pre-release is a user choice after the scan) → review → approve → commit; push/release/VM-upgrade only on explicit user direction (order is the user's call) |
| Update wrapper + OpenClaw | `openclaw-update` (default follows current channel; `--pre`/`--stable` switch channel; `--version=<tag>` pins both) |
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

1. Use `/sync-upstream` to check for new upstream OpenClaw releases and apply changes.
   It scans **both channels** (latest stable + newest beta); syncing stable is the
   default, and after the scan the user chooses whether to also cut a wrapper
   **pre-release** for a validated beta (feeds the `openclaw-update --pre` channel)
2. Implement changes and commit locally
3. The remaining steps — push, tag, GitHub release, and upgrading the local VM —
   have **no fixed order**. The user decides the sequence each time: sometimes the
   VM is upgraded first to validate, sometimes the wrapper release goes out first
   and the VM upgrade waits for community feedback.

Never push, tag, create a release, or upgrade the VM autonomously — wait for explicit
user direction on what to do and in which order.

**Release channels** (versioning policy): the wrapper version always mirrors a real
upstream OpenClaw version — never invented. Upstream **stable** → GitHub **Latest**
release; a **validated** upstream **beta** → GitHub **pre-release** (`openclaw-update
--pre`). Branch checkouts still update via `git pull` of `main` (now done by
`openclaw-update` stage 1 since the v2026.7.1 cutover), so keep `main`'s `VERSION` at
the last **stable** and cut a beta pre-release as a tag **one commit ahead of `main`**
(that extra commit only stamps `VERSION`/`CLAUDE.md` to the beta). This keeps
branch-following stable users honestly labeled while the pre-release snapshot
carries the beta stamp. Details: memory `[[wrapper-versioning-and-distribution]]`.

## Config Editing Rules

Detailed rules in `.claude/rules/json-config.md` (auto-applied for JSON/JSON5 files).
When unsure about a field's parent key, check `memory/config.md`.

## Removal / Deletion Rules

- Before claiming a CLI command, config option, or feature doesn't exist, verify against at least two sources (official docs + code/community search)
- Never remove functionality based on a single source — ask user to test if you can't verify yourself
- When editing docs that reference upstream features, WebFetch the upstream docs first
