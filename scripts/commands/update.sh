#!/bin/bash
# openclaw-update: Update OpenClaw to the latest version
# Called via thin wrapper: ~/bin/openclaw-update -> this script

# SC1091: Dynamic source of _common.sh
# shellcheck disable=SC1091
source "$(dirname "$0")/_common.sh"

SANDBOX=false
FORCE=false
TARGET_VERSION=""
for arg in "$@"; do
    case "$arg" in
        --sandbox) SANDBOX=true ;;
        --force) FORCE=true ;;
        --version=*) TARGET_VERSION="${arg#--version=}" ;;
        --help|-h)
            echo "$MSG_CMD_UPDATE_USAGE"
            echo ""
            echo "$MSG_CMD_UPDATE_DESC"
            echo ""
            echo "$MSG_CMD_UPDATE_OPTIONS"
            echo "$MSG_CMD_UPDATE_SANDBOX_OPT"
            echo "$MSG_CMD_UPDATE_FORCE_OPT"
            echo "$MSG_CMD_UPDATE_VERSION_OPT"
            echo ""
            echo "$MSG_CMD_UPDATE_TIP"
            exit 0
            ;;
    esac
done

# Auto-detect stale system-level service and self-repair
if grep -q "systemctl status openclaw" ~/bin/openclaw-status 2>/dev/null; then
    echo "$MSG_UPDATE_AUTO_UPGRADE"
    # VM: migrate from system-level to user-level service
    orb -m "$OPENCLAW_VM_NAME" bash -lc "sudo systemctl stop openclaw 2>/dev/null || true"
    orb -m "$OPENCLAW_VM_NAME" bash -lc "sudo systemctl disable openclaw 2>/dev/null || true"
    orb -m "$OPENCLAW_VM_NAME" bash -lc "sudo rm -f /etc/systemd/system/openclaw.service && sudo systemctl daemon-reload"
    orb -m "$OPENCLAW_VM_NAME" bash -lc "sudo loginctl enable-linger \$(whoami)"
    orb -m "$OPENCLAW_VM_NAME" bash -lc "systemctl --user enable openclaw-gateway.service 2>/dev/null || true"
    # Mac: regenerate all commands
    OPENCLAW_LANG="$_OPENCLAW_LANG" OPENCLAW_VM_NAME="$OPENCLAW_VM_NAME" \
        bash "$OPENCLAW_REPO_DIR/scripts/refresh-mac-commands.sh" 2>/dev/null || true
    echo "$MSG_UPDATE_AUTO_UPGRADE_DONE"
fi

# Ensure .env exists with at least Bonjour vars
if ! orb -m "$OPENCLAW_VM_NAME" bash -lc 'test -f ~/.openclaw/.env' 2>/dev/null; then
    orb -m "$OPENCLAW_VM_NAME" bash -lc 'mkdir -p ~/.openclaw && printf "# OpenClaw Environment Variables\nOPENCLAW_DISABLE_BONJOUR=1\n" > ~/.openclaw/.env && chmod 600 ~/.openclaw/.env'
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
orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && git remote prune origin >/dev/null && git fetch --quiet --prune --tags --force"

if [ -n "$TARGET_VERSION" ]; then
    # Explicit version pin: validate tag exists upstream; allow beta/rc/alpha.
    if ! orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && git rev-parse --verify '$TARGET_VERSION^{commit}' >/dev/null 2>&1"; then
        # shellcheck disable=SC2059
        printf "$MSG_ERR_VERSION_NOT_FOUND\n" "$TARGET_VERSION"
        exit 1
    fi
    LATEST_TAG="$TARGET_VERSION"
    # shellcheck disable=SC2059
    printf "$MSG_UPDATE_VERSION_USING\n" "$LATEST_TAG"
else
    LATEST_TAG=$(orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && git tag -l 'v*' | grep -v -e '-beta' -e '-rc' -e '-alpha' | sort -V | tail -1")
    if [ -z "$LATEST_TAG" ]; then
        echo "$MSG_ERR_NO_VERSION"
        exit 1
    fi
    echo "  -> $LATEST_TAG"
fi

# --- Ensure Node.js >= 24 (upstream recommends 24.x LTS) ---
echo "$MSG_UPDATE_NODE_CHECK"
NODE_VERSION=$(orb -m "$OPENCLAW_VM_NAME" bash -lc 'node --version 2>/dev/null' || echo "")
NODE_MAJOR="${NODE_VERSION#v}"
NODE_MAJOR="${NODE_MAJOR%%.*}"
if [ -n "$NODE_MAJOR" ] && [ "$NODE_MAJOR" -ge 24 ] 2>/dev/null; then
    # shellcheck disable=SC2059
    printf "$MSG_UPDATE_NODE_OK\n" "$NODE_VERSION"
else
    # shellcheck disable=SC2059
    printf "$MSG_UPDATE_NODE_UPGRADING\n" "$NODE_VERSION"
    # Unhold first in case a previous version was pinned, then install + re-hold at 24
    if orb -m "$OPENCLAW_VM_NAME" bash -lc "sudo apt-mark unhold nodejs 2>/dev/null; curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash - && sudo apt-get install -y nodejs && sudo apt-mark hold nodejs"; then
        NEW_NODE=$(orb -m "$OPENCLAW_VM_NAME" bash -lc 'node --version')
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
CODEX_OLD=$(orb -m "$OPENCLAW_VM_NAME" bash -lc 'codex --version 2>/dev/null' || true)
if [ -z "$CODEX_OLD" ]; then
    echo "$MSG_UPDATE_CODEX_CLI_INSTALLING"
else
    # shellcheck disable=SC2059
    printf "$MSG_UPDATE_CODEX_CLI_UPGRADING\n" "$CODEX_OLD"
fi
# Capture npm output to a log (not the terminal — npm's "added/changed N packages"
# + allow-scripts banner would otherwise stream and garble). On failure the real
# error is surfaced from the log instead of vanishing into /dev/null.
if orb -m "$OPENCLAW_VM_NAME" bash -lc 'sudo npm install -g @openai/codex > ~/.openclaw/.update-codex.log 2>&1'; then
    CODEX_NEW=$(orb -m "$OPENCLAW_VM_NAME" bash -lc 'codex --version 2>/dev/null' || echo "unknown")
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
orb -m "$OPENCLAW_VM_NAME" bash -lc '
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
LAST_BUILT=$(orb -m "$OPENCLAW_VM_NAME" bash -lc 'cat ~/.openclaw/.build-version 2>/dev/null' || echo "")
case "$LAST_BUILT" in
    v2026.5.*)
        if ! orb -m "$OPENCLAW_VM_NAME" bash -lc 'test -f ~/.openclaw/.sandbox-hash-format-v54' 2>/dev/null; then
            echo "$MSG_UPDATE_SANDBOX_HASH_MIGRATE"
            orb -m "$OPENCLAW_VM_NAME" bash -lc '
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
CURRENT_HEAD=$(orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && git rev-parse HEAD 2>/dev/null")
TAG_COMMIT=$(orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && git rev-parse '$LATEST_TAG^{commit}' 2>/dev/null")
BUILT_VERSION=$(orb -m "$OPENCLAW_VM_NAME" bash -lc "cat ~/.openclaw/.build-version 2>/dev/null" || echo "")
if [ "$CURRENT_HEAD" = "$TAG_COMMIT" ] && [ "$BUILT_VERSION" = "$LATEST_TAG" ] && [ "$FORCE" = false ] && [ "$SANDBOX" = false ]; then
    echo -e "$MSG_CMD_UPDATE_ALREADY_CURRENT"
    # Still refresh Mac commands in case openclaw-orbstack repo changed
    OPENCLAW_LANG="$_OPENCLAW_LANG" OPENCLAW_VM_NAME="$OPENCLAW_VM_NAME" \
        bash "$OPENCLAW_REPO_DIR/scripts/refresh-mac-commands.sh" 2>/dev/null || true
    exit 0
fi

echo "$MSG_CMD_UPDATE_STOPPING"
# Suppress the openclaw CLI startup banner/tagline (stdout) so it doesn't
# interleave with the wrapper's progress output. Same for the two gateway starts.
orb -m "$OPENCLAW_VM_NAME" bash -lc "openclaw gateway stop >/dev/null 2>&1"
GATEWAY_STOPPED=true
trap 'if [ "$GATEWAY_STOPPED" = true ]; then
    echo "$MSG_CMD_UPDATE_RECOVER"
    orb -m "$OPENCLAW_VM_NAME" bash -lc "openclaw gateway start >/dev/null 2>&1" || true
fi' EXIT

# -q on both checkouts suppresses the "detached HEAD" advisory + "HEAD is now at"
# lines (noise that interleaves with the spinner). Real errors still hit stderr.
orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && git checkout -q -- . 2>/dev/null; git checkout -q '$LATEST_TAG'"

# Derive npm package version from git tag (v2026.3.13 -> 2026.3.13)
NPM_VERSION="${LATEST_TAG#v}"

# Clear build marker so a failed build won't be skipped next time
orb -m "$OPENCLAW_VM_NAME" bash -lc "rm -f ~/.openclaw/.build-version" 2>/dev/null || true

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
if orb -m "$OPENCLAW_VM_NAME" bash -lc "sudo npm install -g openclaw@$NPM_VERSION > ~/.openclaw/.update-npm.log 2>&1"; then
    # Verify package completeness (e.g. npm tarball may ship without dist/control-ui/)
    # against root's prefix (sudo npm root -g) — must expand inside the VM, not on Mac.
    # Check both index.js (canonical since ≤v2026.3.x) and entry.js (legacy reference).
    # shellcheck disable=SC2016
    if orb -m "$OPENCLAW_VM_NAME" bash -lc 'R=$(sudo npm root -g); { test -f "$R/openclaw/dist/index.js" || test -f "$R/openclaw/dist/entry.js"; } && test -d "$R/openclaw/dist/control-ui" && test -d "$R/openclaw/dist/extensions"'; then
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
orb -m "$OPENCLAW_VM_NAME" bash -lc "echo '$LATEST_TAG' > ~/.openclaw/.build-version"

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
    HASH_DATA=$(orb -m "$OPENCLAW_VM_NAME" bash -lc '
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
        # on success; show the real docker error tail on failure.
        _t0=$(date +%s)
        if orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && sg docker -c './scripts/sandbox-setup.sh' > ~/.openclaw/.update-sandbox-base.log 2>&1"; then
            save_sandbox_hash base scripts/docker/sandbox/Dockerfile Dockerfile.sandbox scripts/sandbox-setup.sh
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
        if orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && sg docker -c './scripts/sandbox-common-setup.sh' > ~/.openclaw/.update-sandbox-common.log 2>&1"; then
            save_sandbox_hash common scripts/docker/sandbox/Dockerfile.common Dockerfile.sandbox-common scripts/sandbox-common-setup.sh
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
        if orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && sg docker -c './scripts/sandbox-browser-setup.sh' > ~/.openclaw/.update-sandbox-browser.log 2>&1"; then
            save_sandbox_hash browser scripts/docker/sandbox/Dockerfile.browser Dockerfile.sandbox-browser scripts/sandbox-browser-setup.sh
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
    orb -m "$OPENCLAW_VM_NAME" bash -lc "rm -f ~/.openclaw/.sandbox-build-hash" 2>/dev/null || true
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
orb -m "$OPENCLAW_VM_NAME" bash -lc "sudo rm -rf /root/.openclaw /root/.config/systemd/user/openclaw-gateway.service* 2>/dev/null" || true
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
orb -m "$OPENCLAW_VM_NAME" bash -lc '
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
orb -m "$OPENCLAW_VM_NAME" bash -lc '
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

orb -m "$OPENCLAW_VM_NAME" bash -lc "mkdir -p ~/.openclaw && echo '=== sudo doctor --fix (plugin deps) ===' > ~/.openclaw/.update-doctor.log && yes n | sudo --preserve-env=HOME openclaw doctor --fix >> ~/.openclaw/.update-doctor.log 2>&1" || true
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
orb -m "$OPENCLAW_VM_NAME" bash -lc "sudo chown -R \$(id -u):\$(id -g) ~/.openclaw/ ~/.npm/ 2>/dev/null; sudo chown \$(id -u):\$(id -g) ~/.config/systemd/user/openclaw-*.service* 2>/dev/null; sudo rm -rf /tmp/jiti 2>/dev/null" || true
# 3) Config migration + systemd user service fix (as regular user, after chown).
#    Same `yes n` rationale as above — keeps the @clack/prompts orphan-archive
#    confirm from cancelling the whole doctor pass.
orb -m "$OPENCLAW_VM_NAME" bash -lc "echo '=== doctor --fix (config migration) ===' >> ~/.openclaw/.update-doctor.log && yes n | openclaw doctor --fix >> ~/.openclaw/.update-doctor.log 2>&1" || true

# --- Startup optimization drop-in (upstream recommended for VM/ARM: docs/vps.md) ---
# Bridge pattern: if the main service already has NODE_COMPILE_CACHE, upstream has taken
# over — remove our drop-in. Otherwise, ensure it exists for older service files.
# shellcheck disable=SC2016
orb -m "$OPENCLAW_VM_NAME" bash -lc '
DROPIN_DIR=~/.config/systemd/user/openclaw-gateway.service.d
DROPIN=$DROPIN_DIR/openclaw-orbstack.conf
SERVICE=~/.config/systemd/user/openclaw-gateway.service
if grep -q NODE_COMPILE_CACHE "$SERVICE" 2>/dev/null; then
    rm -f "$DROPIN"
    rmdir "$DROPIN_DIR" 2>/dev/null || true
elif [ ! -f "$DROPIN" ]; then
    mkdir -p "$DROPIN_DIR" /var/tmp/openclaw-compile-cache
    printf "[Service]\nEnvironment=NODE_COMPILE_CACHE=/var/tmp/openclaw-compile-cache\nEnvironment=OPENCLAW_NO_RESPAWN=1\n" > "$DROPIN"
fi
systemctl --user daemon-reload
' 2>/dev/null || true

# --- Gateway PATH drop-in (Linux only; upstream #75233 fix is macOS LaunchAgent only as of v2026.5.2) ---
# `openclaw gateway install` on Linux derives PATH from the user shell at install time, so
# version-manager / package-manager dirs (.bun/bin, .npm-global/bin, .nix-profile/bin,
# .local/share/pnpm) leak into the gateway service PATH. Functionally harmless (Node lives
# at /usr/bin/node) but doctor flags it as advisory on every run. We pin a canonical PATH
# via drop-in. systemd evaluates drop-ins after the main unit; the LAST `Environment=PATH=`
# wins, so this overrides anything upstream sets. The 99- prefix also wins lexicographic
# ordering against any later drop-ins openclaw or third parties might ship.
# shellcheck disable=SC2016
orb -m "$OPENCLAW_VM_NAME" bash -lc '
DROPIN_DIR=~/.config/systemd/user/openclaw-gateway.service.d
DROPIN=$DROPIN_DIR/99-openclaw-orbstack-path.conf
mkdir -p "$DROPIN_DIR"
printf "[Service]\nEnvironment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n" > "$DROPIN"
systemctl --user daemon-reload
' 2>/dev/null || true

echo "$MSG_CMD_UPDATE_STARTING"
orb -m "$OPENCLAW_VM_NAME" bash -lc "openclaw gateway start >/dev/null 2>&1"

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
REAUTH_HITS=$(orb -m "$OPENCLAW_VM_NAME" bash -lc 'grep -F "re-authenticate this profile" ~/.openclaw/.update-doctor.log 2>/dev/null | head -5' || true)
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
