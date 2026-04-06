---
name: sync-upstream
description: Sync with latest upstream OpenClaw stable release.
disable-model-invocation: true
---

# Upstream Sync

Sync openclaw-orbstack with the latest stable release from `openclaw/openclaw`.

The goal is to keep our OrbStack installer, config templates, docs, and CLAUDE.md
aligned with upstream changes — without blindly copying. Each upstream change needs
to be evaluated for whether and how it affects our wrapper project.

Upstream repo: https://github.com/openclaw/openclaw

## Step 1 — Version check

Run these two checks in parallel to save time:

- **Upstream latest stable tag**:
  ```bash
  git ls-remote --tags https://github.com/openclaw/openclaw.git 'v*' \
    | awk '{print $2}' | sed 's|refs/tags/||' \
    | grep -v -e '-beta' -e '-rc' -e '-alpha' \
    | sort -V | tail -1
  ```
- **Our version**: read the `VERSION` file in the repo root.

Compare them. If already in sync, tell the user and stop — there's nothing to do.

If `git ls-remote` fails (network issue, repo moved), fall back to:
```bash
gh release list -R openclaw/openclaw --limit 5
```

## Step 2 — Read upstream release notes

Fetch the release notes for every version we're behind on:

```bash
gh release view <tag> -R openclaw/openclaw
```

If multiple versions behind, read ALL intermediate releases from oldest to newest.
Order matters because later releases may revert or supersede earlier changes.

Classify each change into one of these categories. This classification drives
Step 3 — it tells you which of our files to inspect:

| Category | Files likely affected in our project |
|----------|--------------------------------------|
| New config options | `templates/openclaw.json.example`, `CLAUDE.md` |
| Breaking config changes | `templates/openclaw.json.example`, possibly `local/openclaw.json` (user decides) |
| New CLI commands / flags | `docs/commands.md`, `scripts/commands/`, `scripts/refresh-mac-commands.sh` |
| New built-in tools | `templates/openclaw.json.example` (sandbox allow list + model config), `docs/commands.md` |
| New chat commands | `docs/commands.md` (e.g., `/dreaming`, `/tasks`) |
| Removed features / commands | `docs/commands.md`, `templates/openclaw.json.example`, Docs Snapshot in memory |
| New install dependencies | `openclaw-orbstack-setup.sh` (dependency install steps) |
| New channels or providers | `docs/`, Docs Snapshot in memory |
| New experimental features | `templates/openclaw.json.example` (config), `docs/commands.md` (commands) |
| Bug fixes only | Usually just a version bump — no structural changes needed |

**Docs Snapshot location**: The Docs Snapshot lives in auto-memory (`memory/MEMORY.md`),
not in `CLAUDE.md`. Update it when providers, channels, or major features change.

## Step 3 — Impact analysis

This is the most important step. For each upstream change, verify whether our
project actually needs updating by reading the relevant files (don't guess from
memory — the codebase may have changed since last time).

Use Grep and Read to find the specific locations. For example:
- A new config option → grep `templates/openclaw.json.example` for the parent key
  to see if the section exists and where to insert it.
- A new CLI command or flag → check `docs/commands.md` for existing documentation
  and `scripts/commands/` to see if a wrapper already exists.
- A new chat command → check `docs/commands.md` for where to add it.
- A new built-in tool → check sandbox allow list in the config template and
  any model config sections (e.g., `videoGenerationModel`, `musicGenerationModel`).
- A removed feature → grep across docs and templates to find stale references.
- A version bump → read `VERSION` and grep `CLAUDE.md` for the version string.

Present a numbered table so the user can cherry-pick:

| # | Upstream change | Our file(s) | What to update |
|---|----------------|-------------|----------------|

Always include version bumps as separate line items:
- `VERSION` file
- `CLAUDE.md` header (`**Version:** vX.Y.Z`)

**Do not edit any files yet.** The user needs to review first because some changes
(especially breaking config changes) may not apply to our use case, or the user
may want to handle them differently.

## Step 4 — Wait for approval

Ask the user which items to apply. Accept "all", specific numbers, or exclusions
like "all except #3".

## Step 5 — Execute

Apply the approved changes. When changes are to independent files, edit them in
parallel for speed. When changes depend on each other (e.g., a new config option
that also needs a doc update referencing it), apply them sequentially to ensure
consistency.

For config template edits (`templates/openclaw.json.example`):
- Preserve JSON5 formatting (comments, trailing commas).
- Add new options near related existing options, not at the end of the file.
- Include a brief comment explaining what the option does.

For command docs edits (`docs/commands.md`):
- New CLI commands/flags → add to the appropriate section with version annotation.
- New chat commands (e.g., `/dreaming`) → add explanation near the related CLI section.
- New built-in tools with config → include a config snippet reference.
- Removed commands → remove from docs or mark as removed with version.
- New advanced/system commands → add to the "高级命令" list at the bottom.

## Step 6 — Validate

Run in parallel:
```bash
bash -n openclaw-orbstack-setup.sh
```
```bash
shellcheck openclaw-orbstack-setup.sh
```

Also validate any other shell scripts that were modified (e.g., files in `scripts/`).

If validation fails, fix the issue before proceeding. Don't ask the user to fix
lint errors introduced by this sync.

## Step 7 — Commit

Create a single commit:
```
chore: sync with upstream vX.Y.Z
```

If syncing across multiple versions, use the final target version in the message
and mention the range in the body:
```
chore: sync with upstream vX.Y.Z

Covers changes from vA.B.C through vX.Y.Z.
```

## Step 8 — Stop

Do not push, tag, or create a release. The user needs to test locally first
(e.g., reinstall the VM, verify config changes work). Remind them of this:

> Changes committed locally. Please test before pushing. When ready, I can help
> push and create a release.
