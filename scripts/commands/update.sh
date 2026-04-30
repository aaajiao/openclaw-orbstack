#!/bin/bash
# openclaw-update: Update OpenClaw to the latest version
# Called via thin wrapper: ~/bin/openclaw-update -> this script

# SC1091: Dynamic source of _common.sh
# shellcheck disable=SC1091
source "$(dirname "$0")/_common.sh"

SANDBOX=false
FORCE=false
for arg in "$@"; do
    case "$arg" in
        --sandbox) SANDBOX=true ;;
        --force) FORCE=true ;;
        --help|-h)
            echo "$MSG_CMD_UPDATE_USAGE"
            echo ""
            echo "$MSG_CMD_UPDATE_DESC"
            echo ""
            echo "$MSG_CMD_UPDATE_OPTIONS"
            echo "$MSG_CMD_UPDATE_SANDBOX_OPT"
            echo "$MSG_CMD_UPDATE_FORCE_OPT"
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
orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && git remote prune origin && git fetch --prune --tags --force"
LATEST_TAG=$(orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && git tag -l 'v*' | grep -v -e '-beta' -e '-rc' -e '-alpha' | sort -V | tail -1")
if [ -z "$LATEST_TAG" ]; then
    echo "$MSG_ERR_NO_VERSION"
    exit 1
fi
echo "  -> $LATEST_TAG"

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

# --- Migrate old single hash → per-image hashes (no rebuild) ---
orb -m "$OPENCLAW_VM_NAME" bash -lc '
    if [ -f ~/.openclaw/.sandbox-build-hash ] && [ ! -f ~/.openclaw/.sandbox-hash-base ]; then
        cd ~/openclaw
        cat Dockerfile.sandbox scripts/sandbox-setup.sh 2>/dev/null | sha256sum | cut -c1-64 > ~/.openclaw/.sandbox-hash-base
        cat Dockerfile.sandbox-common scripts/sandbox-common-setup.sh 2>/dev/null | sha256sum | cut -c1-64 > ~/.openclaw/.sandbox-hash-common
        cat Dockerfile.sandbox-browser scripts/sandbox-browser-setup.sh 2>/dev/null | sha256sum | cut -c1-64 > ~/.openclaw/.sandbox-hash-browser
        rm -f ~/.openclaw/.sandbox-build-hash
    fi
' 2>/dev/null || true

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
orb -m "$OPENCLAW_VM_NAME" bash -lc "openclaw gateway stop"
GATEWAY_STOPPED=true
trap 'if [ "$GATEWAY_STOPPED" = true ]; then
    echo "$MSG_CMD_UPDATE_RECOVER"
    orb -m "$OPENCLAW_VM_NAME" bash -lc "openclaw gateway start" 2>/dev/null || true
fi' EXIT

orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && git checkout -- . 2>/dev/null; git checkout '$LATEST_TAG'"

# Derive npm package version from git tag (v2026.3.13 -> 2026.3.13)
NPM_VERSION="${LATEST_TAG#v}"

# Clear build marker so a failed build won't be skipped next time
orb -m "$OPENCLAW_VM_NAME" bash -lc "rm -f ~/.openclaw/.build-version" 2>/dev/null || true

# shellcheck disable=SC2059
printf "$MSG_PKG_INSTALL_VERSION\n" "$NPM_VERSION"

# Try prebuilt npm package; fall back to source build on failure
NPM_OK=false
if orb -m "$OPENCLAW_VM_NAME" bash -lc "sudo npm install -g openclaw@$NPM_VERSION"; then
    # Verify package completeness (e.g. npm tarball may ship without dist/control-ui/)
    # $(npm root -g) must expand inside the VM, not on Mac
    # Check both index.js (canonical since ≤v2026.3.x) and entry.js (legacy reference)
    # shellcheck disable=SC2016
    if orb -m "$OPENCLAW_VM_NAME" bash -lc '{ test -f $(npm root -g)/openclaw/dist/index.js || test -f $(npm root -g)/openclaw/dist/entry.js; } && test -d $(npm root -g)/openclaw/dist/control-ui && test -d $(npm root -g)/openclaw/dist/extensions'; then
        NPM_OK=true
        echo "$MSG_PKG_INSTALL_OK"
    else
        echo "$MSG_PKG_INSTALL_INCOMPLETE"
    fi
else
    echo "$MSG_PKG_INSTALL_FAIL"
fi

if [ "$NPM_OK" = false ]; then
    echo "$MSG_BUILD_FALLBACK"
    # Ensure pnpm is available for source build
    orb -m "$OPENCLAW_VM_NAME" bash -lc '
if ! command -v pnpm &>/dev/null; then
    if ! command -v npm &>/dev/null; then
        echo "  '"$MSG_CMD_UPDATE_NPM_REINSTALL"'"
        sudo apt-get install --reinstall -y nodejs
    fi
    sudo corepack enable 2>/dev/null || sudo npm install -g pnpm
fi
'
    if orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && pnpm install && pnpm build && pnpm ui:build && sudo npm install -g ."; then
        echo "$MSG_BUILD_FALLBACK_OK"
    else
        echo "$MSG_BUILD_FALLBACK_FAIL"
        exit 1
    fi
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
    # Single orb round-trip: read 3 old hashes + calculate 3 new hashes
    HASH_DATA=$(orb -m "$OPENCLAW_VM_NAME" bash -lc '
        cat ~/.openclaw/.sandbox-hash-base 2>/dev/null || echo none
        cat ~/.openclaw/.sandbox-hash-common 2>/dev/null || echo none
        cat ~/.openclaw/.sandbox-hash-browser 2>/dev/null || echo none
        cd ~/openclaw
        cat Dockerfile.sandbox scripts/sandbox-setup.sh 2>/dev/null | sha256sum | cut -c1-64
        cat Dockerfile.sandbox-common scripts/sandbox-common-setup.sh 2>/dev/null | sha256sum | cut -c1-64
        cat Dockerfile.sandbox-browser scripts/sandbox-browser-setup.sh 2>/dev/null | sha256sum | cut -c1-64
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
        echo "$MSG_BUILD_PATIENCE"
        start_progress
        if orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && sg docker -c './scripts/sandbox-setup.sh'" 2>/dev/null; then
            stop_progress
            save_sandbox_hash base Dockerfile.sandbox scripts/sandbox-setup.sh
        else
            stop_progress
            BUILD_COMMON=false  # cascade: skip common if base failed
        fi
    else
        echo "$MSG_CMD_UPDATE_SANDBOX_BASE_SKIP"
    fi

    # --- Common ---
    if [ "$BUILD_COMMON" = true ]; then
        [ "$BUILD_BASE" = true ] && [ "$OLD_COMMON" = "$NEW_COMMON" ] && echo "$MSG_CMD_UPDATE_SANDBOX_COMMON_CASCADE"
        echo "$MSG_CMD_UPDATE_SANDBOX_COMMON"
        echo "$MSG_BUILD_PATIENCE"
        start_progress
        if orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && sg docker -c './scripts/sandbox-common-setup.sh'" 2>/dev/null; then
            stop_progress
            save_sandbox_hash common Dockerfile.sandbox-common scripts/sandbox-common-setup.sh
        else
            stop_progress
            echo "$MSG_CMD_UPDATE_SANDBOX_COMMON_FAIL"
        fi
    else
        echo "$MSG_CMD_UPDATE_SANDBOX_COMMON_SKIP"
    fi

    # --- Browser (independent) ---
    if [ "$BUILD_BROWSER" = true ]; then
        echo "$MSG_CMD_UPDATE_SANDBOX_BROWSER"
        echo "$MSG_BUILD_PATIENCE"
        start_progress
        if orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && sg docker -c './scripts/sandbox-browser-setup.sh'" 2>/dev/null; then
            stop_progress
            save_sandbox_hash browser Dockerfile.sandbox-browser scripts/sandbox-browser-setup.sh
        else
            stop_progress
            echo "$MSG_CMD_UPDATE_SANDBOX_BROWSER_FAIL"
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

# Ensure systemd service matches current install path (npm vs source build)
echo "$MSG_CMD_UPDATE_DOCTOR"
# Defensive cleanup: absorb any /root ghost state left behind by a prior bare
# `sudo openclaw doctor --fix` (without --preserve-env=HOME) that would otherwise
# keep re-polluting subsequent sudo runs.
orb -m "$OPENCLAW_VM_NAME" bash -lc "sudo rm -rf /root/.openclaw /root/.config/systemd/user/openclaw-gateway.service* 2>/dev/null" || true
# 1) Bundled plugin runtime deps need root for global npm prefix — run sudo FIRST
#    to avoid non-sudo run leaving partial npm state that blocks the sudo install.
#    --preserve-env=HOME ensures doctor reads the correct user config (~/.openclaw/)
#    Output captured to ~/.openclaw/.update-doctor.log for post-mortem.
orb -m "$OPENCLAW_VM_NAME" bash -lc "mkdir -p ~/.openclaw && echo '=== sudo doctor --fix (plugin deps) ===' > ~/.openclaw/.update-doctor.log && sudo --preserve-env=HOME openclaw doctor --fix >> ~/.openclaw/.update-doctor.log 2>&1" || true
# 2) Restore file ownership in case sudo created/modified files under ~/.openclaw/
#    or left root-owned systemd user service files under ~/.config/systemd/user/.
#    ~/.npm/ MUST be chowned too: with --preserve-env=HOME, sudo npm writes into
#    user's ~/.npm/_cacache/ as root, which blocks any later non-root npm call
#    (npm 7+ safety check → EACCES). Surfaced by 4.23's merged 17-pkg plugin
#    runtime deps install (2026-04-24, Node 24 on Ubuntu 24).
orb -m "$OPENCLAW_VM_NAME" bash -lc "sudo chown -R \$(id -u):\$(id -g) ~/.openclaw/ ~/.npm/ 2>/dev/null; sudo chown \$(id -u):\$(id -g) ~/.config/systemd/user/openclaw-*.service* 2>/dev/null" || true
# 3) Config migration + systemd user service fix (as regular user, after chown)
orb -m "$OPENCLAW_VM_NAME" bash -lc "echo '=== doctor --fix (config migration) ===' >> ~/.openclaw/.update-doctor.log && openclaw doctor --fix >> ~/.openclaw/.update-doctor.log 2>&1" || true

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

echo "$MSG_CMD_UPDATE_STARTING"
orb -m "$OPENCLAW_VM_NAME" bash -lc "openclaw gateway start"

# Refresh Mac commands (picks up any wrapper changes)
OPENCLAW_LANG="$_OPENCLAW_LANG" OPENCLAW_VM_NAME="$OPENCLAW_VM_NAME" \
    bash "$OPENCLAW_REPO_DIR/scripts/refresh-mac-commands.sh" 2>/dev/null || true

echo "$MSG_CMD_UPDATE_DONE"
echo "$MSG_CMD_UPDATE_DOCTOR_LOG"
if [ "$SANDBOX" = false ]; then
    echo "$MSG_CMD_UPDATE_SANDBOX_HINT"
fi
