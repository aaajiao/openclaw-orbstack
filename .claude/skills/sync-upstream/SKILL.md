---
name: sync-upstream
description: Sync with upstream OpenClaw. Scans both channels (stable + beta); after the scan the user chooses whether to sync stable and/or cut a beta pre-release.
disable-model-invocation: true
---

# Upstream Sync

Sync openclaw-orbstack with the latest release from `openclaw/openclaw`.

The goal is to keep our OrbStack installer, config templates, docs, and CLAUDE.md
aligned with upstream changes — without blindly copying. Each upstream change needs
to be evaluated for whether and how it affects our wrapper project.

Upstream repo: https://github.com/openclaw/openclaw

## Channels: one scan, then the user picks the target

There is one invocation (`/sync-upstream`, no flags), but the wrapper serves TWO
channels, mirroring `openclaw-update`:

- **Stable** — upstream latest stable tag → sync `main`, stamp
  `VERSION`/`CLAUDE.md`, feeds the GitHub **Latest** release. This is the
  default target when it's behind.
- **Beta** — newest upstream tag **including pre-releases** → a wrapper
  **pre-release tag** that `openclaw-update --pre` picks up. This is the beta
  channel's supply chain — but cutting one is always an **explicit user choice**,
  made AFTER the Step 1 scan (never assumed from the invocation).

Version ordering across channels must be prerelease-aware: translate the semver
`-` separator to `~` before `sort -V` and back after (plain `sort -V` mis-orders
`v2026.7.1-beta.5` vs `v2026.7.1`). A stable release outranks its own
prereleases — so when the newest upstream tag IS a stable, the beta channel has
nothing extra to offer and the run is just a stable sync.

**Beta release policy** (matters in Steps 3/7/8): the wrapper only cuts a
pre-release for a **validated** upstream beta — typically one the user's VM
already runs, or one the user explicitly wants to validate via this release.
Confirm which it is before Step 5. Sync **content** lands on `main` as usual,
but the beta version stamp does **not** — see the beta notes in Steps 3, 7 and 8.

## Step 1 — Scan both channels

Gather all four positions in parallel:

- **Upstream latest stable**:
  ```bash
  git ls-remote --tags https://github.com/openclaw/openclaw.git 'v*' \
    | awk '{print $2}' | sed 's|refs/tags/||' \
    | grep -v -e '-beta' -e '-rc' -e '-alpha' \
    | sort -V | tail -1
  ```
  (The beta/rc/alpha filter here is **only to find the stable channel's tip**.
  Step 2 still reads the beta/rc notes in between; do not let this filter leak
  into Step 2.)
- **Upstream newest tag incl. prereleases** (prerelease-aware sort):
  ```bash
  git ls-remote --tags https://github.com/openclaw/openclaw.git 'v*' \
    | awk '{print $2}' | sed 's|refs/tags/||' | grep -v '\^{}' \
    | sed 's/-/~/g' | sort -V | tail -1 | sed 's/~/-/g'
  ```
- **Our stable position**: the `VERSION` file in the repo root.
- **Our beta position**: `VERSION` on `main` is intentionally pinned to the last
  stable, so the beta channel's position is our newest wrapper tag:
  ```bash
  git tag -l 'v*' | sed 's/-/~/g' | sort -V | tail -1 | sed 's/~/-/g'
  ```

If `git ls-remote` fails (network issue, repo moved), fall back to:
```bash
gh release list -R openclaw/openclaw --limit 5
```

**Then pick the target — the beta option is the user's call:**

| Scan result | What to do |
|-------------|------------|
| Both channels in sync | Report and stop — nothing to do. (Exception: if `main` has moved since our newest beta tag was cut, offer a **re-cut** of that tag instead of silently stopping.) |
| Upstream stable > our `VERSION` | Stable sync is the default target — proceed to Step 2 with it. |
| Only the beta is ahead (upstream newest prerelease > our newest wrapper tag, stable in sync) | **Ask the user** whether to cut a wrapper beta pre-release for it (mention whether their VM already runs it — validated betas only). Yes → proceed with the beta target; no → stop. |
| Both ahead (a newer stable AND an even newer prerelease exist) | Stable sync first; after it lands, ask whether to also cut a beta pre-release for the newer prerelease. |

## Step 2 — Read upstream release notes

We sync **to Step 1's target**, but stable release notes are
**cumulative summaries** — they roll up several beta/rc cycles and **omit per-PR
detail that only appears in the beta/rc release notes**. (Example: v2026.5.26 folded
in the skipped 5.23–5.25 betas as one rolled-up section.) So read the full range,
betas included — not just the stable tags.

First enumerate every release between our version and the target, **keeping
beta/rc tags** (do NOT reuse Step 1's `grep -v` filter here):

```bash
git ls-remote --tags https://github.com/openclaw/openclaw.git 'v*' \
  | awk '{print $2}' | sed 's|refs/tags/||' | grep -v '\^{}' \
  | sort -V
```

If `git ls-remote` fails here, fall back to `gh` and keep the beta/rc rows (do NOT
filter them out):
```bash
gh release list -R openclaw/openclaw --limit 30
```

Take every tag greater than our current position (stable target: `VERSION`;
beta target: our newest wrapper tag from Step 1) up to and including the target —
**keep the beta/rc entries**. Then read each one's notes, oldest to newest:

```bash
gh release view <tag> -R openclaw/openclaw
```

Read ALL intermediate releases (stable **and** beta/rc) from oldest to newest.
Order matters: later releases may revert or supersede earlier changes, and a change
first shipped in a beta is often documented **only** in that beta's notes even when
the stable rollup glosses over it.

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
| **Doctor / wrapper-impacting CLI behavior** | **`scripts/commands/update.sh`** (verify non-interactive flow still completes), `lang/*.sh` (hint messages) |
| Bug fixes only | Usually just a version bump — no structural changes needed |

**Docs Snapshot location**: The Docs Snapshot lives in auto-memory (`memory/MEMORY.md`),
not in `CLAUDE.md`. Update it when providers, channels, or major features change.

### Doctor / non-interactive flow scan (mandatory)

`scripts/commands/update.sh` runs `openclaw doctor --fix` **twice** (sudo for plugin
deps, then non-sudo for config migration) with stdin redirected to a log file.
Any upstream change that introduces new interactive prompts can silently break
the entire post-install flow — `@clack/prompts` treats redirected-stdin EOF as
`Setup cancelled` and skips all subsequent doctor steps (state migration, systemd
service repair, security audit).

**While reading release notes, flag any line matching these patterns** (case-insensitive):

- `doctor` + (`interactive` | `confirm` | `prompt` | `Yes/No` | `require ... confirmation`)
- `@clack/prompts` | `clack` (the prompt library)
- `Setup cancelled` | `Setup canceled`
- `--non-interactive` | `--yes` | `--assume-yes` (if upstream adds these as opt-out flags, we can drop our `yes n` workaround)
- `doctor --fix` behavior changes
- `archive` / `migrate` / `repair` paired with "ask" / "prompt"

**For each flagged change, perform an explicit verification step in Step 3:**

1. **Read `scripts/commands/update.sh`** around the two `doctor --fix` invocations
   (grep for `doctor --fix` — their line numbers move as the file grows). The
   wrapper has a **two-layer non-interactive defense**: (a) primary — orphan
   transcripts are pre-archived just above the doctor calls so doctor sees zero
   orphans and never raises the v2026.4.29 confirm; (b) defense-in-depth — both
   calls pipe `yes n |` in case a new or shifted prompt slips through.
2. **Classify the new prompt type:**
   - **Yes/No confirm** — `yes n` answers "No". Verify "No" is the **safe / non-destructive** default
     (e.g., "Archive orphan transcripts? No" → preserves files, ✅ safe). If "No"
     is destructive ("Delete corrupted lock?" → Yes is required), the wrapper needs
     to answer differently or fall back.
   - **Select / multi-choice** — `yes n` does NOT match a list option. Plan a
     wrapper fix: `expect` script, a `printf "1\n"`-style answer, or wait for an
     upstream `--non-interactive` flag.
   - **Free-text input** — `yes n` will inject "n" as the answer. Almost always wrong.
     Plan a wrapper fix.
3. **Add the doctor change to the impact table** with explicit "verify both
   `doctor --fix` invocations in `scripts/commands/update.sh` still complete" in
   the action column, even if no other file needs touching. Treat it as a blocker
   until verified.
4. **If a wrapper fix is needed**, list it as a separate impact-table row so the
   user can approve the script change alongside the version bump.

**Reference incident**: v2026.4.29 #73106 added the
`Archive N orphan transcript files?` confirm. Our update.sh hit `Setup cancelled`
right after plugin registry refresh, leaving systemd service repair on the floor.
First fixed in commit `33434d7` by piping `yes n` to both doctor invocations; later
hardened by pre-archiving orphan transcripts before the doctor calls (so the prompt
never fires), with `yes n` kept as the fallback. Whenever release notes mention
doctor + interactivity, **assume the same regression class until proven otherwise**.

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
- **A doctor / interactive-prompt change** → read `scripts/commands/update.sh`
  around the two `doctor --fix` invocations (grep for `doctor --fix`) and verify
  the pre-archive + `yes n |` defense still answers safely (see the "Doctor /
  non-interactive flow scan" section above). If a new prompt type (select,
  free-text) would break the pipe, propose a wrapper fix as a separate impact-table row.
- **If the sync target crosses the v2026.7.1 stable line** → run the mandatory
  "v2026.7.1 stable cutover (one-time)" checklist below and fold its rows into
  the impact table.

### v2026.7.1 stable cutover (one-time, mandatory when applicable)

Check this **every sync**, even if it usually doesn't apply: if the sync target
is the **first STABLE release `>= v2026.7.1`**, the
impact table **MUST** include these rows — this is a one-time structural cutover,
not an optional cleanup, so don't let it silently fall through a normal version-bump
sync. A **prerelease** target never triggers it — the cutover requires a stable
tag users can land on:

| # | Cutover item | File(s) | What to update |
|---|---------------|---------|-----------------|
| a | Remove the auto-pull block | `scripts/refresh-mac-commands.sh` | Delete the `git pull` block in the generated `openclaw-update` wrapper (marked with a `DEFERRED CUTOVER` comment — grep for it). After removal, `openclaw-update`'s built-in wrapper stage becomes the **sole** wrapper-delivery path; branch checkouts no longer auto-update themselves. |
| b | Update README auto-pull note | `README.md` | Rewrite the auto-pull/cutover note (near the update-commands section) to say the cutover has happened — no more silent `git pull` on branch checkouts. |
| c | Update CLAUDE.md deferred-cutover paragraphs | `CLAUDE.md` | Update the "Deferred cutover" paragraph under Single-Command Update Model to state it's done, not pending — remove the "deferred to v2026.7.1 stable" language. |
| d | Retire the deprecated aliases — **already done 2026-07-13** | — | `openclaw-stop`, `openclaw-start`, `openclaw-doctor`, `openclaw-whatsapp`, `openclaw-telegram` were removed outright on 2026-07-13 by explicit user decision, ahead of this cutover (`refresh-mac-commands.sh` also cleans stale alias files from `~/bin`). Nothing left to ask — just verify no stale alias references have resurfaced. |

Only skip this checklist if the sync target is still below v2026.7.1, or if a
prior sync already executed it (check `CLAUDE.md`'s Single-Command Update Model
section — if it no longer says "deferred", the cutover already happened).

Present a numbered table so the user can cherry-pick:

| # | Upstream change | Our file(s) | What to update |
|---|----------------|-------------|----------------|

Always include version bumps as separate line items:
- `VERSION` file
- `CLAUDE.md` header (`**Version:** vX.Y.Z`)

**Beta-target exception**: when the target is a prerelease, these two stamps do
**NOT** land on `main` — `main` stays honestly labeled at the last stable
(branch checkouts auto-pull `main`, and those users are on the stable channel).
List the stamps in the table anyway, marked "release-time stamp commit, not on
main" — they are applied in Step 8's release flow, not in Step 5.

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

**If this sync touched doctor / non-interactive flow**, also remind the user that
post-upgrade verification means checking `~/.openclaw/.update-doctor.log` for
`Setup cancelled` lines. A clean log = doctor finished all passes. Any
`Setup cancelled` = a new interactive prompt slipped past our checks.

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

**Beta target**: same single content commit on `main`, message
`chore: sync with upstream vX.Y.Z-beta.N` — but it must NOT touch `VERSION` or
the `CLAUDE.md` version header (those stay at the last stable; the beta stamp
happens only in Step 8's tag-only commit).

## Step 8 — Stop

Changes are committed locally. **Do not** push, tag, create a release, or upgrade
the VM on your own. The remaining steps — push, tag, GitHub release, and VM upgrade
— have no fixed order; the user decides the sequence each time (sometimes VM-first
to validate, sometimes wrapper-release-first with the VM upgrade waiting on
community feedback). Report the committed state and wait for explicit direction:

> Changes committed locally. Push / release / VM upgrade are up to you — tell me
> what to do and in what order.

**Beta release flow** (execute only on explicit user direction, but state
it in the report so the user knows what "release" will do):

1. Push `main` (content commit only, still stamped at the last stable).
2. Create the **stamp commit** on top of `main`: set `VERSION` and the
   `CLAUDE.md` version header to `vX.Y.Z-beta.N`, commit message
   `chore: stamp vX.Y.Z-beta.N pre-release`. Do NOT advance `main` to it —
   it is reachable only via the tag.
3. Tag that commit `vX.Y.Z-beta.N` and push the tag. **Re-cut** (same beta,
   `main` moved): make a fresh stamp commit on the new tip and force-move the
   tag (`git tag -f` + `git push -f origin <tag>`), then update the existing
   release to the new tag target.
4. `gh release create <tag> --prerelease` — release notes in **English only**.
   Never mark it Latest; the stable release keeps that label.
