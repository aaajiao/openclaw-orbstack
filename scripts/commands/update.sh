#!/bin/bash
# openclaw-update: single command that updates BOTH layers.
#
# STAGE 1 (Mac-side only, no vm_exec anywhere — works without a VM): update the
# openclaw-orbstack WRAPPER (this repo checkout) on its current release
# channel. The channel is inferred from the repo checkout state, or switched
# explicitly via --pre / --stable / --version=<tag>. See the CHANNEL MODEL
# comment below for the full state machine. Because this stage never touches
# the VM, the hidden `openclaw-update --wrapper-only` utility flag works even
# without one.
#
# STAGE 2 (VM-side, unchanged from the previous single-purpose openclaw-update):
# update OpenClaw inside the VM to the version this wrapper's VERSION file is
# now aligned with (override via --version=<tag>).
#
# Called via thin wrapper: ~/bin/openclaw-update -> this script

# SC1091: Dynamic source of _common.sh
# shellcheck disable=SC1091
source "$(dirname "$0")/_common.sh"

SANDBOX=false
FORCE=false
TARGET_VERSION=""
PRE=false
STABLE=false
WRAPPER_ONLY=false
AFTER_SELF=false
for arg in "$@"; do
    case "$arg" in
        --sandbox) SANDBOX=true ;;
        --force) FORCE=true ;;
        --version=*) TARGET_VERSION="${arg#--version=}" ;;
        --pre) PRE=true ;;
        --stable) STABLE=true ;;
        # Hidden flags (not documented in --help):
        #   --wrapper-only : run stage 1 only, then exit — update the wrapper
        #                    without touching the VM (also handy for testing
        #                    the channel logic on a machine with no VM).
        #   --after-self   : set by stage 1's own re-exec after it moves the
        #                    wrapper, so the freshly checked-out script skips
        #                    stage 1 and runs stage 2 directly.
        --wrapper-only) WRAPPER_ONLY=true ;;
        --after-self) AFTER_SELF=true ;;
        --help|-h)
            echo "$MSG_CMD_UPDATE_USAGE"
            echo ""
            echo "$MSG_CMD_UPDATE_DESC"
            echo ""
            echo "$MSG_CMD_UPDATE_OPTIONS"
            echo "$MSG_CMD_UPDATE_PRE_OPT"
            echo "$MSG_CMD_UPDATE_STABLE_OPT"
            echo "$MSG_CMD_UPDATE_VERSION_OPT"
            echo "$MSG_CMD_UPDATE_SANDBOX_OPT"
            echo "$MSG_CMD_UPDATE_FORCE_OPT"
            echo ""
            echo "$MSG_CMD_UPDATE_TIP"
            exit 0
            ;;
        *)
            # Unknown flag or bare arg (e.g. the space form `--version v...`,
            # which does not match the `--version=*` glob). Fail loudly instead
            # of silently falling through to the default version-pin path.
            # shellcheck disable=SC2059
            printf "$MSG_CMD_UPDATE_UNKNOWN_OPT\n" "$arg"
            echo "$MSG_CMD_UPDATE_USAGE"
            exit 1
            ;;
    esac
done

if [ "$PRE" = true ] && [ "$STABLE" = true ]; then
    echo "$MSG_UPDATE_CHANNEL_CONFLICT"
    exit 1
fi

# ============================================================================
# STAGE 1: wrapper self-update (100% Mac-side git, no vm_exec — works without
# a VM).
#
# CHANNEL MODEL (inferred from the repo checkout, plus one pin marker file
# ~/bin/.openclaw-pin):
#   - Pin marker present            => wrapper is pinned; do NOT move it.
#   - BRANCH checkout, no flag      => `git pull` the branch here (since the
#                                      v2026.7.1 cutover this stage is the sole
#                                      wrapper-delivery path — the generated
#                                      ~/bin shim no longer auto-pulls).
#   - DETACHED on a prerelease tag  => channel pre: target = newest tag overall.
#   - DETACHED otherwise            => channel stable: target = newest
#                                      non-prerelease tag.
#   Explicit --pre / --stable / --version=<tag> override all of the above.
#
# Skipped entirely when re-invoked via --after-self (stage 1 already ran in
# the parent process before the re-exec below).
# ============================================================================
if [ "$AFTER_SELF" = false ]; then
    WRAPPER_MOVED=false
    PIN_FILE="$HOME/bin/.openclaw-pin"

    GIT_OK=false
    if git -C "$OPENCLAW_REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
        GIT_OK=true
    fi

    if [ "$GIT_OK" = true ]; then
        OLD_VERSION=$(git -C "$OPENCLAW_REPO_DIR" describe --tags --always 2>/dev/null || echo "unknown")

        # Fetch hygiene: --force --prune tolerate rewritten refs (this repo's
        # own tags are few, but the flags are harmless and let a re-pointed
        # release tag — e.g. a same-day beta re-cut — come through cleanly).
        echo "$MSG_UPDATE_WRAPPER_FETCHING"
        git -C "$OPENCLAW_REPO_DIR" fetch --tags --quiet --force --prune 2>/dev/null || true

        WRAPPER_TARGET_TAG=""
        SKIP_ANCESTOR_CHECK=false
        RESOLVE_ATTEMPTED=false

        if [ -n "$TARGET_VERSION" ]; then
            # --version=<tag>: pin the WRAPPER too, but only if the wrapper repo
            # actually has this tag. If not, leave the wrapper (and any existing
            # pin) untouched and let stage 2 apply the tag to OpenClaw only —
            # today's --version behavior, preserved exactly.
            if git -C "$OPENCLAW_REPO_DIR" rev-parse --verify "$TARGET_VERSION^{commit}" >/dev/null 2>&1; then
                WRAPPER_TARGET_TAG="$TARGET_VERSION"
                SKIP_ANCESTOR_CHECK=true
                # shellcheck disable=SC2059
                printf "$MSG_UPDATE_VERSION_WRAPPER_MATCH\n" "$TARGET_VERSION"
            else
                # shellcheck disable=SC2059
                printf "$MSG_UPDATE_VERSION_OPENCLAW_ONLY\n" "$TARGET_VERSION"
            fi
        elif [ "$PRE" = true ]; then
            echo "$MSG_UPDATE_CHANNEL_PRE"
            rm -f "$PIN_FILE"
            RESOLVE_ATTEMPTED=true
            # Newest tag overall (includes pre-releases). sort -V is NOT semver-
            # prerelease-aware — it ranks `X.Y.Z-beta.N` ABOVE `X.Y.Z`, the
            # opposite of semver. Translate the semver `-` separator to `~`
            # (which GNU/Apple sort -V both order BEFORE the release) so a
            # stable release outranks its own prerelease, then translate back.
            WRAPPER_TARGET_TAG=$(git -C "$OPENCLAW_REPO_DIR" tag -l 'v*' | sed 's/-/~/g' | sort -V | tail -1 | sed 's/~/-/g')
        elif [ "$STABLE" = true ]; then
            echo "$MSG_UPDATE_CHANNEL_STABLE"
            rm -f "$PIN_FILE"
            RESOLVE_ATTEMPTED=true
            # Latest NON-prerelease tag.
            WRAPPER_TARGET_TAG=$(git -C "$OPENCLAW_REPO_DIR" tag -l 'v*' | grep -v -e '-beta' -e '-rc' -e '-alpha' | sort -V | tail -1)
            # EXEMPT from the ancestor no-op check below: an explicit channel
            # return is intentional — a beta user moving BACK to the stable tag
            # would otherwise find that tag is an ancestor of their beta HEAD
            # and see a false "already up to date". (The VM-side OpenClaw
            # downgrade that follows in stage 2 is still refused without
            # --force by its own existing guard — that stays correct.)
            SKIP_ANCESTOR_CHECK=true
        elif [ -f "$PIN_FILE" ]; then
            PINNED_TAG=$(tr -d '[:space:]' < "$PIN_FILE")
            # shellcheck disable=SC2059
            printf "$MSG_UPDATE_WRAPPER_PINNED\n" "$PINNED_TAG"
        elif git -C "$OPENCLAW_REPO_DIR" symbolic-ref -q HEAD >/dev/null 2>&1; then
            # Branch checkout: pull the branch here — the ~/bin shim's silent
            # auto-pull was removed at the v2026.7.1 stable cutover, making
            # stage 1 the sole wrapper-delivery path. If the pull moved HEAD,
            # WRAPPER_MOVED triggers the same regenerate + re-exec path a tag
            # checkout uses, so stage 2 runs the freshly pulled script.
            OLD_HEAD=$(git -C "$OPENCLAW_REPO_DIR" rev-parse HEAD 2>/dev/null || echo "")
            if git -C "$OPENCLAW_REPO_DIR" pull -q 2>/dev/null; then
                NEW_HEAD=$(git -C "$OPENCLAW_REPO_DIR" rev-parse HEAD 2>/dev/null || echo "")
                if [ -n "$OLD_HEAD" ] && [ "$OLD_HEAD" != "$NEW_HEAD" ]; then
                    WRAPPER_MOVED=true
                fi
            else
                echo "$MSG_UPDATE_WRAPPER_PULL_FAIL"
            fi
        else
            # Detached HEAD, no channel flag: infer the channel from the
            # currently checked-out tag.
            RESOLVE_ATTEMPTED=true
            CURRENT_TAG=$(git -C "$OPENCLAW_REPO_DIR" describe --tags --exact-match 2>/dev/null || echo "")
            case "$CURRENT_TAG" in
                *-beta*|*-rc*|*-alpha*)
                    WRAPPER_TARGET_TAG=$(git -C "$OPENCLAW_REPO_DIR" tag -l 'v*' | sed 's/-/~/g' | sort -V | tail -1 | sed 's/~/-/g')
                    ;;
                *)
                    WRAPPER_TARGET_TAG=$(git -C "$OPENCLAW_REPO_DIR" tag -l 'v*' | grep -v -e '-beta' -e '-rc' -e '-alpha' | sort -V | tail -1)
                    ;;
            esac
        fi

        if [ "$RESOLVE_ATTEMPTED" = true ] && [ -z "$WRAPPER_TARGET_TAG" ]; then
            echo "$MSG_ERR_NO_VERSION"
            exit 1
        fi

        # --- Never downgrade (inferred paths + --pre; --stable and a wrapper-
        # matched --version=<tag> are EXEMPT, see above) -----------------------
        # If the target commit is already an ancestor of HEAD, the current
        # checkout already includes it -> no-op. This makes a branch user who
        # is AHEAD of the latest stable tag a safe no-op on the default path,
        # and lets --pre still move them onto a newer pre-release tag.
        if [ -n "$WRAPPER_TARGET_TAG" ]; then
            DO_MOVE=true
            if [ "$SKIP_ANCESTOR_CHECK" = false ] && git -C "$OPENCLAW_REPO_DIR" merge-base --is-ancestor "$WRAPPER_TARGET_TAG" HEAD 2>/dev/null; then
                # shellcheck disable=SC2059
                printf "$MSG_UPDATE_WRAPPER_ALREADY\n" "$WRAPPER_TARGET_TAG"
                DO_MOVE=false
            fi
            if [ "$DO_MOVE" = true ]; then
                # -q suppresses the "detached HEAD" advisory (refresh-mac-commands.sh
                # carries no git pull at all since the v2026.7.1 cutover, so the
                # wrapper regeneration below will NOT undo this checkout).
                # shellcheck disable=SC2059
                printf "$MSG_UPDATE_WRAPPER_CHECKOUT\n" "$WRAPPER_TARGET_TAG"
                if ! git -C "$OPENCLAW_REPO_DIR" -c advice.detachedHead=false checkout -q "$WRAPPER_TARGET_TAG" 2>/dev/null; then
                    # shellcheck disable=SC2059
                    printf "$MSG_UPDATE_WRAPPER_CHECKOUT_FAIL\n" "$WRAPPER_TARGET_TAG"
                    exit 1
                fi
                if [ -n "$TARGET_VERSION" ]; then
                    # Explicit --version=<tag> pin: record it so a later plain
                    # `openclaw-update` leaves the wrapper alone until --stable/--pre.
                    mkdir -p "$HOME/bin"
                    printf '%s' "$WRAPPER_TARGET_TAG" > "$PIN_FILE"
                fi
                WRAPPER_MOVED=true
            fi
        fi
    fi

    if [ "$WRAPPER_MOVED" = true ]; then
        NEW_VERSION=$(git -C "$OPENCLAW_REPO_DIR" describe --tags --always 2>/dev/null || echo "unknown")
        # shellcheck disable=SC2059
        printf "$MSG_UPDATE_WRAPPER_DONE\n" "$OLD_VERSION" "$NEW_VERSION"
        # Regenerate ~/bin/openclaw-* from the freshly checked-out tag. Pass
        # through language + VM name so refresh-mac-commands.sh stays
        # non-interactive.
        OPENCLAW_LANG="$_OPENCLAW_LANG" OPENCLAW_VM_NAME="$OPENCLAW_VM_NAME" \
            bash "$OPENCLAW_REPO_DIR/scripts/refresh-mac-commands.sh" 2>/dev/null || true
        if [ "$WRAPPER_ONLY" = true ]; then
            exit 0
        fi
        # Re-exec the just-installed script so stage 2 always runs the target
        # version's own logic, not the (possibly stale) in-memory copy.
        # EXCEPT for an explicit --version=<tag> pin: that may have checked out
        # a tag OLDER than this merge, whose update.sh doesn't know --after-self
        # (v2026.6.11's loud unknown-flag catch-all would abort the run). The
        # pin's stage-2 target comes from --version anyway, so the current
        # in-memory script handles it correctly — no re-exec needed. (Safe even
        # though the on-disk file just changed: git checkout unlinks+recreates,
        # so the running bash keeps reading the old inode.)
        if [ -z "$TARGET_VERSION" ]; then
            exec bash "$0" --after-self "$@"
        fi
    fi

    if [ "$WRAPPER_ONLY" = true ]; then
        exit 0
    fi
fi

# Auto-detect stale system-level service and self-repair
if grep -q "systemctl status openclaw" ~/bin/openclaw-status 2>/dev/null; then
    echo "$MSG_UPDATE_AUTO_UPGRADE"
    # VM: migrate from system-level to user-level service
    vm_exec "sudo systemctl stop openclaw 2>/dev/null || true"
    vm_exec "sudo systemctl disable openclaw 2>/dev/null || true"
    vm_exec "sudo rm -f /etc/systemd/system/openclaw.service && sudo systemctl daemon-reload"
    vm_exec "sudo loginctl enable-linger \$(whoami)"
    vm_exec "systemctl --user enable openclaw-gateway.service 2>/dev/null || true"
    # Mac: regenerate all commands
    OPENCLAW_LANG="$_OPENCLAW_LANG" OPENCLAW_VM_NAME="$OPENCLAW_VM_NAME" \
        bash "$OPENCLAW_REPO_DIR/scripts/refresh-mac-commands.sh" 2>/dev/null || true
    echo "$MSG_UPDATE_AUTO_UPGRADE_DONE"
fi

# Ensure .env exists with at least Bonjour vars
if ! vm_exec 'test -f ~/.openclaw/.env' 2>/dev/null; then
    vm_exec 'mkdir -p ~/.openclaw && printf "# OpenClaw Environment Variables\nOPENCLAW_DISABLE_BONJOUR=1\n" > ~/.openclaw/.env && chmod 600 ~/.openclaw/.env'
    echo "  $MSG_UPDATE_ENV_CREATED"
fi

echo "$MSG_CMD_UPDATE_UPDATING"

# Fetch tags before stopping gateway to check if update is needed
echo "$MSG_CMD_UPDATE_PULLING"
# --prune is required: upstream openclaw has many force-pushed and renamed branches
# (e.g. clawsweeper/* automerge bots), which create refname conflicts on plain fetch.
# Without --prune, fetch fails with "some local refs could not be updated".
# --quiet + prune>/dev/null: openclaw has hundreds of bot branches, so a plain
# fetch floods the terminal with "-> origin/... (forced update)" lines that
# interleave with the wrapper's spinner/echo ("花屏"). Real errors still hit stderr.
vm_exec "cd ~/openclaw && git remote prune origin >/dev/null && git fetch --quiet --prune --tags --force"

if [ -n "$TARGET_VERSION" ]; then
    # Explicit version pin: validate tag exists upstream; allow beta/rc/alpha.
    if ! vm_exec "cd ~/openclaw && git rev-parse --verify '$TARGET_VERSION^{commit}' >/dev/null 2>&1"; then
        # shellcheck disable=SC2059
        printf "$MSG_ERR_VERSION_NOT_FOUND\n" "$TARGET_VERSION"
        exit 1
    fi
    LATEST_TAG="$TARGET_VERSION"
    # shellcheck disable=SC2059
    printf "$MSG_UPDATE_VERSION_USING\n" "$LATEST_TAG"
else
    # Default target = THIS wrapper's own VERSION file (read on the Mac side).
    # Project policy: the wrapper's VERSION mirrors the upstream OpenClaw version it
    # is aligned with. Reading it here (instead of the old "latest stable upstream
    # tag", which filtered out betas and ignored the wrapper entirely) is what makes
    # the two STAGES of this same command compose: stage 1 (above) picks the wrapper's
    # CHANNEL (stable, or a beta via --pre) and moves the repo checkout onto that tag;
    # this stage then installs the OpenClaw version that (possibly just-moved) wrapper
    # is aligned with. Without this, --pre moving the wrapper onto a beta tag would
    # never get the matching OpenClaw beta onto the VM. The --version=* branch above
    # stays the explicit escape hatch (any tag, incl. rollback).
    # Guard the read so a MISSING VERSION file yields the friendly error too: a bare
    # `< file` redirection failure aborts the command substitution under set -e
    # (active via _common.sh) before the [ -z ] check below is ever reached.
    LATEST_TAG=$( [ -f "$OPENCLAW_REPO_DIR/VERSION" ] && tr -d '[:space:]' < "$OPENCLAW_REPO_DIR/VERSION" || true )
    if [ -z "$LATEST_TAG" ]; then
        echo "$MSG_ERR_NO_VERSION"
        exit 1
    fi
    # Validate the wrapper VERSION resolves to a real upstream OpenClaw tag/commit
    # (same check the --version path uses). Guards the case where the wrapper is
    # ahead of any published OpenClaw release.
    if ! vm_exec "cd ~/openclaw && git rev-parse --verify '$LATEST_TAG^{commit}' >/dev/null 2>&1"; then
        # shellcheck disable=SC2059
        printf "$MSG_ERR_WRAPPER_VERSION_NO_MATCH\n" "$LATEST_TAG"
        exit 1
    fi
    # Downgrade guard (default path ONLY — the --version=* pin above is exempt so it
    # can still roll back intentionally). If the wrapper-aligned target is OLDER than
    # the last successfully built OpenClaw and --force was not given, refuse: a routine
    # `openclaw-update` should never silently downgrade the VM's OpenClaw.
    BUILT=$(vm_exec "cat ~/.openclaw/.build-version 2>/dev/null" || echo "")
    if [ -n "$BUILT" ] && [ "$BUILT" != "$LATEST_TAG" ] && [ "$FORCE" = false ]; then
        # sort -V is available on macOS (Apple sort 2.3); this runs Mac-side.
        # sort -V is NOT semver-prerelease-aware: it ranks `X.Y.Z-beta.N` ABOVE
        # `X.Y.Z`, the opposite of semver (a prerelease has LOWER precedence than
        # its final release). Translate the semver `-` prerelease separator to `~`,
        # which GNU/Apple sort -V both order BEFORE the release — restoring correct
        # precedence. Without this, the designed beta→stable transition to the SAME
        # base version (openclaw-update --pre, then --stable once it lands) is
        # misread as a downgrade and refused.
        BUILT_CMP=$(printf '%s' "$BUILT" | sed 's/-/~/g')
        TARGET_CMP=$(printf '%s' "$LATEST_TAG" | sed 's/-/~/g')
        NEWER=$(printf '%s\n%s\n' "$TARGET_CMP" "$BUILT_CMP" | sort -V | tail -1)
        if [ "$NEWER" = "$BUILT_CMP" ] && [ "$TARGET_CMP" != "$BUILT_CMP" ]; then
            # shellcheck disable=SC2059
            printf "$MSG_UPDATE_WRAPPER_DOWNGRADE\n" "$BUILT" "$LATEST_TAG"
            exit 1
        fi
    fi
    # shellcheck disable=SC2059
    printf "$MSG_UPDATE_WRAPPER_ALIGNED\n" "$LATEST_TAG"
fi

# --- Ensure Node.js >= 24.15.0 (24.x LTS line) ---
# OpenClaw >= 2026.7.1 hard-rejects Node runtimes whose bundled SQLite is
# vulnerable to WAL corruption (upstream #106065; engines >=24.15.0 <25 on
# the 24 line) — the CLI, doctor included, refuses to start. A major-only
# check is not enough: a held 24.14.x passes "major >= 24" yet is rejected.
REQUIRED_NODE_FLOOR="24.15.0"
echo "$MSG_UPDATE_NODE_CHECK"
NODE_VERSION=$(vm_exec 'node --version 2>/dev/null' || echo "")
NODE_BARE="${NODE_VERSION#v}"
if [ -n "$NODE_BARE" ] && [ "$(printf '%s\n%s\n' "$REQUIRED_NODE_FLOOR" "$NODE_BARE" | sort -V | head -1)" = "$REQUIRED_NODE_FLOOR" ]; then
    # shellcheck disable=SC2059
    printf "$MSG_UPDATE_NODE_OK\n" "$NODE_VERSION"
else
    # shellcheck disable=SC2059
    printf "$MSG_UPDATE_NODE_UPGRADING\n" "$NODE_VERSION"
    # Unhold first in case a previous version was pinned, then install + re-hold at 24
    if vm_exec "sudo apt-mark unhold nodejs 2>/dev/null; curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash - && sudo apt-get install -y nodejs && sudo apt-mark hold nodejs"; then
        NEW_NODE=$(vm_exec 'node --version')
        # shellcheck disable=SC2059
        printf "$MSG_UPDATE_NODE_UPGRADED\n" "$NEW_NODE"
    else
        echo "$MSG_UPDATE_NODE_FAIL"
    fi
fi

# --- Ensure Codex CLI is present (and up to date) ---
# Required since openclaw v2026.5.14+ for the ChatGPT subscription path:
# upstream PR #82117 makes the runtime fall back to ~/.codex/auth.json when
# OpenClaw's own OAuth refresh fails. We install (first run) or upgrade (latest)
# Codex CLI on every update so the file format stays aligned with OpenAI's
# current auth contract. Failure is non-fatal — gpt-5.* still works via api-key.
echo "$MSG_UPDATE_CODEX_CLI_CHECK"
# `setsid` detaches codex from the controlling terminal. The codex CLI is a Rust
# TUI that initializes the terminal (alt-screen, mouse modes, bg-color + cursor
# queries) even for `--version`, writing those control sequences to /dev/tty —
# which bypasses 2>/dev/null AND the $() stdout capture, and (via orb's PTY) leaks
# back to the Mac terminal, garbling the screen / jumping the cursor at this step
# (this is the ONLY step that runs the codex binary; npm/git/docker aren't TUIs).
# setsid makes /dev/tty unavailable so nothing leaks; stdout (the version string)
# still reaches the capture. </dev/null detaches stdin as well. Verified in-VM:
# `setsid codex --version 2>/dev/null </dev/null` still returns "codex-cli X.Y.Z".
CODEX_OLD=$(vm_exec 'setsid codex --version 2>/dev/null </dev/null' || true)
if [ -z "$CODEX_OLD" ]; then
    echo "$MSG_UPDATE_CODEX_CLI_INSTALLING"
else
    # shellcheck disable=SC2059
    printf "$MSG_UPDATE_CODEX_CLI_UPGRADING\n" "$CODEX_OLD"
fi
# `sudo setsid -w` detaches the install from the controlling terminal. Capturing
# npm's stdout/stderr to a log isn't enough: @openai/codex's postinstall runs the
# codex binary (a Rust TUI) which initializes the terminal — enters the alternate
# screen, homes the cursor, queries it — by opening /dev/tty DIRECTLY, bypassing
# the `> log 2>&1` redirect; orb's PTY then forwards it to the Mac terminal,
# garbling the screen and pushing later output to the top. setsid removes the
# controlling terminal so /dev/tty is unavailable and nothing leaks. `-w` makes
# setsid WAIT for npm and propagate its exit code — the install is multi-second,
# and without -w setsid returns immediately, racing the completeness/version
# checks against a still-running install. `sudo setsid` order (not `setsid sudo`)
# lets sudo keep its tty so a `requiretty` sudoers policy wouldn't break it. On
# failure the real error is surfaced from the log.
if vm_exec 'sudo setsid -w npm install -g @openai/codex > ~/.openclaw/.update-codex.log 2>&1'; then
    CODEX_NEW=$(vm_exec 'setsid codex --version 2>/dev/null </dev/null' || echo "unknown")
    if [ -z "$CODEX_OLD" ]; then
        # shellcheck disable=SC2059
        printf "$MSG_UPDATE_CODEX_CLI_INSTALLED\n" "$CODEX_NEW"
    elif [ "$CODEX_OLD" = "$CODEX_NEW" ]; then
        # shellcheck disable=SC2059
        printf "$MSG_UPDATE_CODEX_CLI_UP_TO_DATE\n" "$CODEX_NEW"
    else
        # shellcheck disable=SC2059
        printf "$MSG_UPDATE_CODEX_CLI_UPGRADED\n" "$CODEX_OLD" "$CODEX_NEW"
    fi
else
    echo "$MSG_UPDATE_CODEX_CLI_FAIL"
    vm_log_tail ".update-codex.log"
fi

# --- Migrate old single hash → per-image hashes (no rebuild) ---
# Hash inputs list both new (≥ v2026.5.3 scripts/docker/sandbox/) and legacy
# (≤ v2026.5.2 root) Dockerfile paths; cat skips missing files via 2>/dev/null
# so the hash reflects whichever layout the current upstream checkout has.
vm_exec '
    if [ -f ~/.openclaw/.sandbox-build-hash ] && [ ! -f ~/.openclaw/.sandbox-hash-base ]; then
        cd ~/openclaw
        cat scripts/docker/sandbox/Dockerfile Dockerfile.sandbox scripts/sandbox-setup.sh 2>/dev/null | sha256sum | cut -c1-64 > ~/.openclaw/.sandbox-hash-base
        cat scripts/docker/sandbox/Dockerfile.common Dockerfile.sandbox-common scripts/sandbox-common-setup.sh 2>/dev/null | sha256sum | cut -c1-64 > ~/.openclaw/.sandbox-hash-common
        cat scripts/docker/sandbox/Dockerfile.browser Dockerfile.sandbox-browser scripts/sandbox-browser-setup.sh 2>/dev/null | sha256sum | cut -c1-64 > ~/.openclaw/.sandbox-hash-browser
        rm -f ~/.openclaw/.sandbox-build-hash
    fi
' 2>/dev/null || true

# --- One-time sandbox hash format migration (v2026.5.4-fix) ---
# Background: v2026.5.3 upstream moved sandbox Dockerfiles from the repo root
# to scripts/docker/sandbox/ AND renamed them. Pre-v2026.5.4-fix wrappers had
# multiple silent hash-tracking bugs because they `cat`d the now-missing
# legacy paths, producing inconsistent hashes that didn't reflect the actual
# Dockerfile content.
#
# CRITICAL FACT (verified at sync time): the sandbox Dockerfile *content* is
# byte-identical across upstream v2026.5.2 → v2026.5.3 → v2026.5.4 — only the
# paths and filenames changed. So any sandbox image built from a v5.x upstream
# checkout is byte-equivalent to one built from v5.4.
#
# Therefore, if the user's last successful build was a v2026.5.x release, we
# can safely overwrite their hash files with the new fallback-aware format
# (matching what this fixed wrapper would compute) and skip the cosmetic
# rebuild that the bare hash mismatch would otherwise trigger. A marker file
# prevents rerunning the migration on subsequent updates.
LAST_BUILT=$(vm_exec 'cat ~/.openclaw/.build-version 2>/dev/null' || echo "")
case "$LAST_BUILT" in
    v2026.5.*)
        if ! vm_exec 'test -f ~/.openclaw/.sandbox-hash-format-v54' 2>/dev/null; then
            echo "$MSG_UPDATE_SANDBOX_HASH_MIGRATE"
            vm_exec '
                cd ~/openclaw
                cat scripts/docker/sandbox/Dockerfile         Dockerfile.sandbox          scripts/sandbox-setup.sh          2>/dev/null | sha256sum | cut -c1-64 > ~/.openclaw/.sandbox-hash-base
                cat scripts/docker/sandbox/Dockerfile.common  Dockerfile.sandbox-common   scripts/sandbox-common-setup.sh   2>/dev/null | sha256sum | cut -c1-64 > ~/.openclaw/.sandbox-hash-common
                cat scripts/docker/sandbox/Dockerfile.browser Dockerfile.sandbox-browser  scripts/sandbox-browser-setup.sh  2>/dev/null | sha256sum | cut -c1-64 > ~/.openclaw/.sandbox-hash-browser
                touch ~/.openclaw/.sandbox-hash-format-v54
            ' 2>/dev/null || true
            echo "$MSG_UPDATE_SANDBOX_HASH_MIGRATE_DONE"
        fi
        ;;
esac

# Check if already on the latest tag AND build succeeded previously
CURRENT_HEAD=$(vm_exec "cd ~/openclaw && git rev-parse HEAD 2>/dev/null")
TAG_COMMIT=$(vm_exec "cd ~/openclaw && git rev-parse '$LATEST_TAG^{commit}' 2>/dev/null")
BUILT_VERSION=$(vm_exec "cat ~/.openclaw/.build-version 2>/dev/null" || echo "")
if [ "$CURRENT_HEAD" = "$TAG_COMMIT" ] && [ "$BUILT_VERSION" = "$LATEST_TAG" ] && [ "$FORCE" = false ] && [ "$SANDBOX" = false ]; then
    echo -e "$MSG_CMD_UPDATE_ALREADY_CURRENT"
    # Still refresh Mac commands in case openclaw-orbstack repo changed
    OPENCLAW_LANG="$_OPENCLAW_LANG" OPENCLAW_VM_NAME="$OPENCLAW_VM_NAME" \
        bash "$OPENCLAW_REPO_DIR/scripts/refresh-mac-commands.sh" 2>/dev/null || true
    exit 0
fi

echo "$MSG_CMD_UPDATE_STOPPING"
# Arm the recovery trap and mark the gateway stopped BEFORE issuing the stop.
# If the stop itself exits non-zero — e.g. an invalid on-disk config makes
# `openclaw gateway stop` fail to load and bail — set -e must not kill the update
# before the trap is even set, or the run dies with no recover message and a
# half-handled gateway (observed 2026-06-24: a 6.9-only `channels.telegram.
# richMessages` key in a 6.8 config aborted the run right at the stop, before the
# trap below). With the trap armed first, a failed stop still triggers recovery;
# the trailing `|| true` lets the run continue so the npm install + doctor +
# final restart reconcile both the version and the (now-valid) config.
GATEWAY_STOPPED=true
trap 'if [ "$GATEWAY_STOPPED" = true ]; then
    echo "$MSG_CMD_UPDATE_RECOVER"
    vm_exec "openclaw gateway start >/dev/null 2>&1" || true
fi' EXIT
# Suppress the openclaw CLI startup banner/tagline (stdout) so it doesn't
# interleave with the wrapper's progress output. Same for the two gateway starts.
vm_exec "openclaw gateway stop >/dev/null 2>&1" || true

# -q on both checkouts suppresses the "detached HEAD" advisory + "HEAD is now at"
# lines (noise that interleaves with the spinner). Real errors still hit stderr.
vm_exec "cd ~/openclaw && git checkout -q -- . 2>/dev/null; git checkout -q '$LATEST_TAG'"

# Derive npm package version from git tag (v2026.3.13 -> 2026.3.13)
NPM_VERSION="${LATEST_TAG#v}"

# Clear build marker so a failed build won't be skipped next time
vm_exec "rm -f ~/.openclaw/.build-version" 2>/dev/null || true

# shellcheck disable=SC2059
printf "$MSG_PKG_INSTALL_VERSION\n" "$NPM_VERSION"

# Install the prebuilt npm package. npm-only since 2026-06-10: the source-build
# fallback was removed now that upstream ships reliable packages (it only ever
# fired here because of the completeness-check bug fixed below, not because npm
# actually failed).
# npm output is captured to ~/.openclaw/.update-npm.log (not streamed) so a
# failure is diagnosable afterwards — nothing reaches the terminal during the
# (multi-minute, ~100MB native-dep) install, so npm's \r progress bars can't
# garble. The step prints elapsed on success and the real npm error tail on fail.
# Completeness is checked against `sudo npm root -g` (root's global prefix,
# /usr/lib/node_modules) to MATCH the `sudo npm install -g` above. A bare
# `npm root -g` resolves the *user's* prefix instead
# (~/.openclaw/workspace/.local/lib/node_modules, the workspace Node), where the
# just-installed package does NOT exist → false "incomplete". That prefix
# mismatch is exactly what forced the source build on every run before 2026-06-10
# (confirmed in-VM: root prefix has dist/{index.js,control-ui,extensions}; user
# prefix has no openclaw at all).
NPM_OK=false
_t0=$(date +%s)
if vm_exec "sudo npm install -g openclaw@$NPM_VERSION > ~/.openclaw/.update-npm.log 2>&1"; then
    # Verify package completeness (e.g. npm tarball may ship without dist/control-ui/)
    # against root's prefix (sudo npm root -g) — must expand inside the VM, not on Mac.
    # Check both index.js (canonical since ≤v2026.3.x) and entry.js (legacy reference).
    # shellcheck disable=SC2016
    if vm_exec 'R=$(sudo npm root -g); { test -f "$R/openclaw/dist/index.js" || test -f "$R/openclaw/dist/entry.js"; } && test -d "$R/openclaw/dist/control-ui" && test -d "$R/openclaw/dist/extensions"'; then
        NPM_OK=true
        printf '%s (%s)\n' "$MSG_PKG_INSTALL_OK" "$(fmt_elapsed "$(($(date +%s) - _t0))")"
    else
        # npm exited 0 but the package is missing files — the log holds the install
        # transcript (pointer, not a tail: there's no error to surface here).
        echo "$MSG_PKG_INSTALL_INCOMPLETE"
        echo "$MSG_PKG_INSTALL_LOG_HINT"
    fi
else
    # npm errored — surface the real failure from the captured log.
    echo "$MSG_PKG_INSTALL_FAIL"
    vm_log_tail ".update-npm.log"
fi

if [ "$NPM_OK" = false ]; then
    # npm is the only install path (source-build fallback removed 2026-06-10). A
    # failure here is genuine — registry down, network, or a truly broken published
    # package — not the old false "incomplete". The FAIL/INCOMPLETE message + npm
    # log hint were already printed above; abort so the operator can fix and retry
    # instead of silently dropping to a multi-minute, screen-garbling source build.
    echo "$MSG_PKG_INSTALL_ABORT"
    exit 1
fi

# Mark build as successful
vm_exec "echo '$LATEST_TAG' > ~/.openclaw/.build-version"

# --- Per-image sandbox hash detection ---
BUILD_BASE=false
BUILD_COMMON=false
BUILD_BROWSER=false

if [ "$SANDBOX" = true ]; then
    # --sandbox flag: force rebuild all
    BUILD_BASE=true; BUILD_COMMON=true; BUILD_BROWSER=true
else
    # Single orb round-trip: read 3 old hashes + calculate 3 new hashes.
    # Hash inputs list both new (≥ v2026.5.3 scripts/docker/sandbox/) and legacy
    # (≤ v2026.5.2 root) paths; cat skips missing files so this works whether
    # the just-checked-out tag uses the new layout or the old one.
    HASH_DATA=$(vm_exec '
        cat ~/.openclaw/.sandbox-hash-base 2>/dev/null || echo none
        cat ~/.openclaw/.sandbox-hash-common 2>/dev/null || echo none
        cat ~/.openclaw/.sandbox-hash-browser 2>/dev/null || echo none
        cd ~/openclaw
        cat scripts/docker/sandbox/Dockerfile        Dockerfile.sandbox         scripts/sandbox-setup.sh         2>/dev/null | sha256sum | cut -c1-64
        cat scripts/docker/sandbox/Dockerfile.common Dockerfile.sandbox-common  scripts/sandbox-common-setup.sh  2>/dev/null | sha256sum | cut -c1-64
        cat scripts/docker/sandbox/Dockerfile.browser Dockerfile.sandbox-browser scripts/sandbox-browser-setup.sh 2>/dev/null | sha256sum | cut -c1-64
    ')
    # Parse 6 lines
    OLD_BASE=$(echo "$HASH_DATA" | sed -n '1p')
    OLD_COMMON=$(echo "$HASH_DATA" | sed -n '2p')
    OLD_BROWSER=$(echo "$HASH_DATA" | sed -n '3p')
    NEW_BASE=$(echo "$HASH_DATA" | sed -n '4p')
    NEW_COMMON=$(echo "$HASH_DATA" | sed -n '5p')
    NEW_BROWSER=$(echo "$HASH_DATA" | sed -n '6p')

    [ "$OLD_BASE" != "$NEW_BASE" ] && BUILD_BASE=true && BUILD_COMMON=true  # cascade
    [ "$OLD_COMMON" != "$NEW_COMMON" ] && BUILD_COMMON=true
    [ "$OLD_BROWSER" != "$NEW_BROWSER" ] && BUILD_BROWSER=true

    if [ "$BUILD_BASE" = true ] || [ "$BUILD_COMMON" = true ] || [ "$BUILD_BROWSER" = true ]; then
        SANDBOX=true
        echo "$MSG_CMD_UPDATE_SANDBOX_CHANGED"
    fi
fi

if [ "$SANDBOX" = true ]; then
    echo "$MSG_CMD_UPDATE_SANDBOX_REBUILD"

    # --- Base ---
    if [ "$BUILD_BASE" = true ]; then
        echo "$MSG_CMD_UPDATE_SANDBOX_BASE"
        # Docker build output → per-image VM log (never the terminal). Show elapsed
        # on success; show the real docker error tail on failure. sandbox_build
        # (scripts/lib/common.sh) also falls back to a direct `docker build` on a
        # setup-script failure — we don't have a distinct _DF message here, so
        # both return 0 (primary) and 2 (fallback) print the same OK line.
        _t0=$(date +%s)
        _rc=0
        sandbox_build base .update-sandbox-base.log || _rc=$?
        if [ "$_rc" -eq 0 ] || [ "$_rc" -eq 2 ]; then
            printf '%s (%s)\n' "$MSG_CMD_UPDATE_SANDBOX_BASE_OK" "$(fmt_elapsed "$(($(date +%s) - _t0))")"
        else
            BUILD_COMMON=false  # cascade: skip common if base failed
            echo "$MSG_CMD_UPDATE_SANDBOX_BASE_FAIL"
            vm_log_tail ".update-sandbox-base.log"
        fi
    else
        echo "$MSG_CMD_UPDATE_SANDBOX_BASE_SKIP"
    fi

    # --- Common ---
    if [ "$BUILD_COMMON" = true ]; then
        [ "$BUILD_BASE" = true ] && [ "$OLD_COMMON" = "$NEW_COMMON" ] && echo "$MSG_CMD_UPDATE_SANDBOX_COMMON_CASCADE"
        echo "$MSG_CMD_UPDATE_SANDBOX_COMMON"
        _t0=$(date +%s)
        _rc=0
        sandbox_build common .update-sandbox-common.log || _rc=$?
        if [ "$_rc" -eq 0 ]; then
            printf '%s (%s)\n' "$MSG_CMD_UPDATE_SANDBOX_COMMON_OK" "$(fmt_elapsed "$(($(date +%s) - _t0))")"
        else
            echo "$MSG_CMD_UPDATE_SANDBOX_COMMON_FAIL"
            vm_log_tail ".update-sandbox-common.log"
        fi
    else
        echo "$MSG_CMD_UPDATE_SANDBOX_COMMON_SKIP"
    fi

    # --- Browser (independent) ---
    if [ "$BUILD_BROWSER" = true ]; then
        echo "$MSG_CMD_UPDATE_SANDBOX_BROWSER"
        _t0=$(date +%s)
        _rc=0
        sandbox_build browser .update-sandbox-browser.log || _rc=$?
        if [ "$_rc" -eq 0 ] || [ "$_rc" -eq 2 ]; then
            printf '%s (%s)\n' "$MSG_CMD_UPDATE_SANDBOX_BROWSER_OK" "$(fmt_elapsed "$(($(date +%s) - _t0))")"
        else
            echo "$MSG_CMD_UPDATE_SANDBOX_BROWSER_FAIL"
            vm_log_tail ".update-sandbox-browser.log"
        fi
    else
        echo "$MSG_CMD_UPDATE_SANDBOX_BROWSER_SKIP"
    fi

    echo "$MSG_CMD_UPDATE_SANDBOX_NOTE"
    # Clean up old monolithic hash file
    vm_exec "rm -f ~/.openclaw/.sandbox-build-hash" 2>/dev/null || true
fi

GATEWAY_STOPPED=false
trap - EXIT

# Run doctor to reconcile service + migrate state after the npm install.
# NOTE: the updater is npm-only now, but a VM upgraded before 2026-06-10 may still
# have a systemd ExecStart pointing at the source checkout (~/openclaw/dist/index.js)
# from a past source-build run. Doctor's service-rewrite prompt is answered "no"
# (yes n, see below) to preserve the operator file, so it is NOT auto-repointed to
# the package install. To move the service onto the npm package, run
# `openclaw gateway install --force` once (manual, intentional).
echo "$MSG_CMD_UPDATE_DOCTOR"
# Defensive cleanup: absorb any /root ghost state left behind by a prior bare
# `sudo openclaw doctor --fix` (without --preserve-env=HOME) that would otherwise
# keep re-polluting subsequent sudo runs.
vm_exec "sudo rm -rf /root/.openclaw /root/.config/systemd/user/openclaw-gateway.service* 2>/dev/null" || true
# 1) Bundled plugin runtime deps need root for global npm prefix — run sudo FIRST
#    to avoid non-sudo run leaving partial npm state that blocks the sudo install.
#    --preserve-env=HOME ensures doctor reads the correct user config (~/.openclaw/)
#    Output captured to ~/.openclaw/.update-doctor.log for post-mortem. The log is
#    overwritten each run — per operator preference (2026-06-10) we keep only the
#    current log, not the timestamped archives the wrapper used to rotate.
#    `yes n` keeps doctor non-interactive past v2026.4.29 #73106 (orphan-archive
#    confirm) and v2026.5.2 line 310 (Gateway-service-rewrite confirm).
#    Orphan transcripts are pre-archived below — doctor sees zero orphans and the
#    "Archive N orphan transcripts?" prompt does NOT appear in the normal flow.
#    The `yes n` remains as defense-in-depth (in case prompts shift or new ones
#    appear) and to safely answer "no" to the v5.2 Gateway service rewrite prompt:
#    "no" preserves the operator's existing service file, which is the safe default.
#    If a fresh service file is genuinely needed, run interactive
#    `openclaw doctor --fix` manually or reinstall via setup.sh.
#    v2026.5.3 (#74831): doctor --fix also silently migrates the legacy monolithic
#    sandbox registry into per-runtime shard files under
#    ~/.openclaw/state/sandbox/runtimes/*.json. No prompt; nothing to handle here.
#    Future debugging: don't look for one big sandbox registry JSON — it's sharded.
# Keep only the current doctor log. Older wrapper versions rotated the log into
# timestamped archives (.update-doctor.<UTC-timestamp>.log, last 3 kept); per
# operator preference (2026-06-10) a single live ~/.openclaw/.update-doctor.log —
# truncated + rewritten by the sudo pass below — is enough. Drop any archives left
# by previous wrappers: the `.*.log` glob can't match the live `.update-doctor.log`
# (nothing sits between `.update-doctor.` and the final `.log`), and the second glob
# clears legacy numbered `.update-doctor.log.{1..5}` files.
# shellcheck disable=SC2016
vm_exec '
mkdir -p ~/.openclaw
rm -f ~/.openclaw/.update-doctor.*.log ~/.openclaw/.update-doctor.log.[0-9]*
' 2>/dev/null || true

# Pre-archive orphan transcripts so doctor's "Archive N orphan transcripts?" prompt
# (added in v2026.4.29 #73106) doesn't appear. Doctor's archive action just renames
# .jsonl files NOT referenced in sessions.json to *.deleted.<timestamp>; we do the
# same here with a UUID substring grep, which is collision-safe (32-char hex = 128-bit
# unique). After this, no orphans → doctor finishes without the orphan prompt.
# Walks every agent's sessions/ dir to handle multi-agent setups.
#
# Timestamp format MUST match upstream's `formatSessionArchiveTimestamp()`:
#   `new Date().toISOString().replaceAll(":", "-")` → `2026-05-03T08-15-30.123Z`
# Upstream's archive cleanup (`cleanupArchivedSessionTranscripts`, called by
# `saveSessionStore` when `session.maintenance.pruneAfter` is set, default 30d)
# parses this format via regex /^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}(\.\d{3})?Z$/.
# Files NOT matching the regex are unrecognized → never auto-pruned, sit forever.
# We use bash `date -u +%Y-%m-%dT%H-%M-%SZ` which produces a regex-compliant
# (without ms suffix) timestamp.
# shellcheck disable=SC2016
vm_exec '
TS=$(date -u +%Y-%m-%dT%H-%M-%SZ)
shopt -s nullglob
for SESSION_DIR in ~/.openclaw/agents/*/sessions; do
    STORE=$SESSION_DIR/sessions.json
    [ -f "$STORE" ] || continue
    for f in "$SESSION_DIR"/*.jsonl; do
        base=$(basename "$f" .jsonl)
        if ! grep -q "$base" "$STORE"; then
            mv "$f" "$f.deleted.$TS"
        fi
    done
done
' 2>/dev/null || true

vm_exec "mkdir -p ~/.openclaw && echo '=== sudo doctor --fix (plugin deps) ===' > ~/.openclaw/.update-doctor.log && yes n | sudo --preserve-env=HOME openclaw doctor --fix >> ~/.openclaw/.update-doctor.log 2>&1" || true
# 2) Restore file ownership in case sudo created/modified files under ~/.openclaw/
#    or left root-owned systemd user service files under ~/.config/systemd/user/.
#    ~/.npm/ MUST be chowned too: with --preserve-env=HOME, sudo npm writes into
#    user's ~/.npm/_cacache/ as root, which blocks any later non-root npm call
#    (npm 7+ safety check → EACCES). Surfaced by 4.23's merged 17-pkg plugin
#    runtime deps install (2026-04-24, Node 24 on Ubuntu 24).
#    /tmp/jiti is jiti's compiled-output cache used by the codex plugin's
#    plugin-sdk-json-schema-runtime require chain. The sudo doctor pass populates
#    it as root with default 0644 perms; user-mode plugin loads then hit
#    EACCES on read (some entries open O_RDWR via jiti's lock path). Wipe so
#    subsequent user passes rebuild the cache with correct ownership.
#    Surfaced 2026-05-15 on v2026.5.14-beta.1: codex plugin failed to load 5×
#    during one update run, leaving Codex harness unregistered until next restart.
vm_exec "sudo chown -R \$(id -u):\$(id -g) ~/.openclaw/ ~/.npm/ 2>/dev/null; sudo chown \$(id -u):\$(id -g) ~/.config/systemd/user/openclaw-*.service* 2>/dev/null; sudo rm -rf /tmp/jiti 2>/dev/null" || true
# 3) Config migration + systemd user service fix (as regular user, after chown).
#    Same `yes n` rationale as above — keeps the @clack/prompts orphan-archive
#    confirm from cancelling the whole doctor pass.
vm_exec "echo '=== doctor --fix (config migration) ===' >> ~/.openclaw/.update-doctor.log && yes n | openclaw doctor --fix >> ~/.openclaw/.update-doctor.log 2>&1" || true

# --- Official plugin sync (lockstep plugins follow the core version) ----------
# Official npm-installed plugins (@openclaw/codex, perplexity, ...) are lockstep-
# versioned with the core, but nothing realigned them during a core install: the
# channel/version sync only runs on `openclaw plugins update --all` (upstream wires
# syncOfficialPluginInstalls to --all only, PR #94225; a bare per-id update honors
# the stored pin and self-reports "up to date" — observed 2026-07-14 with exa/tavily
# stuck on beta.6 after the stable hop). Run the sync here: after doctor + chown
# (writes land in user-owned ~/.openclaw/npm/) and before the gateway start below,
# so the fresh plugin versions load with the one normal start. Installed-but-
# disabled official plugins are synced too — upstream behavior, keeps them aligned
# for whenever they get enabled.
# npm >= 12 guard: `npm view --json` returns arrays even for single hits under
# npm 12, which breaks the update preflight (upstream #106189) — worse, a failed
# update can DISABLE healthy plugins. Skip the sync entirely and tell the operator.
# `yes n` mirrors the doctor calls above: defense-in-depth against any interactive
# prompt appearing in this captured non-TTY run ("no" is always the safe answer).
NPM_MAJOR=$(vm_exec "npm -v 2>/dev/null" | cut -d. -f1 || true)
if [ -n "$NPM_MAJOR" ] && [ "$NPM_MAJOR" -ge 12 ] 2>/dev/null; then
    # shellcheck disable=SC2059
    printf "$MSG_CMD_UPDATE_PLUGINS_NPM12_SKIP\n" "$NPM_MAJOR"
else
    echo "$MSG_CMD_UPDATE_PLUGINS_SYNC"
    if vm_exec "yes n | openclaw plugins update --all > ~/.openclaw/.update-plugins.log 2>&1"; then
        # Surface only the per-plugin outcome lines; the CLI banner is noise here.
        vm_exec 'grep -E "Updated |up to date|Failed" ~/.openclaw/.update-plugins.log' 2>/dev/null | sed 's/^/   /' || true
    else
        echo "$MSG_CMD_UPDATE_PLUGINS_SYNC_FAILED"
        vm_log_tail ".update-plugins.log"
    fi
fi

# --- Startup optimization + PATH drop-ins (upstream recommended for VM/ARM: docs/vps.md) ---
# See scripts/lib/common.sh:write_systemd_dropins for the bridge-pattern /
# PATH-pin rationale (upstream-takeover removal, #75233 PATH leak).
write_systemd_dropins

echo "$MSG_CMD_UPDATE_STARTING"
# `|| true`: `gateway start` only dispatches the systemd start and normally exits 0
# even for a unit that then dies in migration — but if the dispatch itself errors
# (bad unit, transient systemd hiccup), set -e (active via _common.sh) would abort
# HERE, before the health-poll + auto-repair block below can self-heal. Swallow the
# dispatch status so the gateway_healthy poll always governs the outcome.
vm_exec "openclaw gateway start >/dev/null 2>&1" || true

# --- Verify the gateway actually reached a healthy 'running' state -----------
# `openclaw gateway start` only asks systemd to start the unit and returns once the
# start is *dispatched* — it does NOT wait for startup migrations to finish. A boot
# that then dies during migration would otherwise sail past here and the wrapper would
# print "Update complete!" over a dead gateway (observed 2026-07-11 on the beta.2 ->
# beta.5 hop: the `@openclaw/codex` plugin package dir went missing during the core
# install -> "startup migrations did not complete cleanly" -> exit 1 -> crash loop).
# Poll for real readiness (gateway_healthy, scripts/lib/common.sh); if it never comes
# up, self-heal once with `openclaw update repair` — the only path that re-materializes
# a missing plugin package dir (`doctor --fix` does not) — then restart and re-check.
if ! gateway_healthy; then
    echo "$MSG_CMD_UPDATE_GATEWAY_UNHEALTHY"
    vm_exec "openclaw update repair >/dev/null 2>&1" || true
    vm_exec "openclaw gateway restart >/dev/null 2>&1" || true
    if gateway_healthy; then
        echo "$MSG_CMD_UPDATE_GATEWAY_REPAIRED"
        # `openclaw update repair` re-installs plugins from the STABLE `latest` npm
        # dist-tag, so on a beta/rc/alpha target it can leave official plugins drifted
        # below the gateway version. Non-fatal (the gateway runs), but surface a re-pin
        # hint so the operator can realign them.
        case "$LATEST_TAG" in
            *-beta*|*-rc*|*-alpha*)
                # shellcheck disable=SC2059
                printf "$MSG_CMD_UPDATE_GATEWAY_REPIN_HINT\n" "$NPM_VERSION"
                ;;
        esac
    else
        echo "$MSG_CMD_UPDATE_GATEWAY_FAILED"
        exit 1
    fi
fi

# Refresh Mac commands (picks up any wrapper changes)
OPENCLAW_LANG="$_OPENCLAW_LANG" OPENCLAW_VM_NAME="$OPENCLAW_VM_NAME" \
    bash "$OPENCLAW_REPO_DIR/scripts/refresh-mac-commands.sh" 2>/dev/null || true

echo "$MSG_CMD_UPDATE_DONE"

# Surface doctor follow-up actions that would otherwise be buried in the log.
# Currently catches PR #82777's "re-authenticate this profile" warning emitted
# when doctor strips a legacy oauthRef sidecar but can't decrypt it to inline
# the credentials — the profile is left invalid and routing silently falls
# through to the next profile in `auth.order.*`. Without this surface, the
# user sees a clean "Update complete!" and only notices later when /status
# shows the wrong auth label.
# shellcheck disable=SC2016
REAUTH_HITS=$(vm_exec 'grep -F "re-authenticate this profile" ~/.openclaw/.update-doctor.log 2>/dev/null | head -5' || true)
if [ -n "$REAUTH_HITS" ]; then
    printf "\n\033[1;33m%s\033[0m\n" "$MSG_CMD_UPDATE_DOCTOR_REAUTH_HEADER"
    # shellcheck disable=SC2001  # sed is clearer than the bash builtin for per-line indent
    echo "$REAUTH_HITS" | sed 's/^/   /'
    printf "\n   \033[1m%s\033[0m\n\n" "$MSG_CMD_UPDATE_DOCTOR_REAUTH_HINT"
fi

echo "$MSG_CMD_UPDATE_DOCTOR_LOG"
echo "$MSG_CMD_UPDATE_DOCTOR_ORPHAN_HINT"
if [ "$SANDBOX" = false ]; then
    echo "$MSG_CMD_UPDATE_SANDBOX_HINT"
fi
