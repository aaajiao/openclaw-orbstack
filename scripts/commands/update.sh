#!/bin/bash
# openclaw-update: Update OpenClaw to the latest version
# Called via thin wrapper: ~/bin/openclaw-update -> this script

# shellcheck source=_common.sh
source "$(dirname "$0")/_common.sh"

SANDBOX=false
for arg in "$@"; do
    case "$arg" in
        --sandbox) SANDBOX=true ;;
        --help|-h)
            echo "$MSG_CMD_UPDATE_USAGE"
            echo ""
            echo "$MSG_CMD_UPDATE_DESC"
            echo ""
            echo "$MSG_CMD_UPDATE_OPTIONS"
            echo "$MSG_CMD_UPDATE_SANDBOX_OPT"
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
    # Mac: fix stale commands
    cat > ~/bin/openclaw-status << 'FIXEOF'
#!/bin/bash
set -e
_VM="openclaw-vm"; [ -f "$HOME/bin/.openclaw-vm" ] && source "$HOME/bin/.openclaw-vm" && _VM="${OPENCLAW_VM:-$_VM}"
orb -m "$_VM" bash -lc "openclaw gateway status"
FIXEOF
    cat > ~/bin/openclaw-logs << 'FIXEOF'
#!/bin/bash
set -e
_VM="openclaw-vm"; [ -f "$HOME/bin/.openclaw-vm" ] && source "$HOME/bin/.openclaw-vm" && _VM="${OPENCLAW_VM:-$_VM}"
orb -m "$_VM" bash -lc "openclaw logs --follow"
FIXEOF
    cat > ~/bin/openclaw-restart << 'FIXEOF'
#!/bin/bash
set -e
_VM="openclaw-vm"; [ -f "$HOME/bin/.openclaw-vm" ] && source "$HOME/bin/.openclaw-vm" && _VM="${OPENCLAW_VM:-$_VM}"
orb -m "$_VM" bash -lc "openclaw gateway restart"
FIXEOF
    cat > ~/bin/openclaw-stop << 'FIXEOF'
#!/bin/bash
set -e
_VM="openclaw-vm"; [ -f "$HOME/bin/.openclaw-vm" ] && source "$HOME/bin/.openclaw-vm" && _VM="${OPENCLAW_VM:-$_VM}"
orb -m "$_VM" bash -lc "openclaw gateway stop"
FIXEOF
    cat > ~/bin/openclaw-start << 'FIXEOF'
#!/bin/bash
set -e
_VM="openclaw-vm"; [ -f "$HOME/bin/.openclaw-vm" ] && source "$HOME/bin/.openclaw-vm" && _VM="${OPENCLAW_VM:-$_VM}"
orb -m "$_VM" bash -lc "openclaw gateway start"
FIXEOF
    chmod +x ~/bin/openclaw-status ~/bin/openclaw-logs ~/bin/openclaw-restart ~/bin/openclaw-stop ~/bin/openclaw-start
    echo "$MSG_UPDATE_AUTO_UPGRADE_DONE"
fi

# Ensure .env exists with at least Bonjour vars
if ! orb -m "$OPENCLAW_VM_NAME" bash -lc 'test -f ~/.openclaw/.env' 2>/dev/null; then
    orb -m "$OPENCLAW_VM_NAME" bash -lc 'mkdir -p ~/.openclaw && printf "# OpenClaw Environment Variables\nOPENCLAW_DISABLE_BONJOUR=1\nCLAWDBOT_DISABLE_BONJOUR=1\n" > ~/.openclaw/.env && chmod 600 ~/.openclaw/.env'
    echo "  $MSG_UPDATE_ENV_CREATED"
fi

echo "$MSG_CMD_UPDATE_UPDATING"

echo "$MSG_CMD_UPDATE_STOPPING"
orb -m "$OPENCLAW_VM_NAME" bash -lc "openclaw gateway stop"

echo "$MSG_CMD_UPDATE_PULLING"
orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && git fetch --tags"
LATEST_TAG=$(orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && git tag -l 'v*' | grep -vE '-(beta|rc|alpha)' | sort -V | tail -1")
echo "  -> $LATEST_TAG"
orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && git checkout '$LATEST_TAG'"

# Ensure pnpm is available (npm/corepack may vanish after apt upgrade)
orb -m "$OPENCLAW_VM_NAME" bash -lc '
if ! command -v pnpm &>/dev/null; then
    if ! command -v npm &>/dev/null; then
        echo "  npm missing, reinstalling Node.js package..."
        sudo apt-get install --reinstall -y nodejs
    fi
    sudo corepack enable 2>/dev/null || sudo npm install -g pnpm
fi
'

echo "$MSG_CMD_UPDATE_INSTALLING"
orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && pnpm install"

echo "$MSG_CMD_UPDATE_BUILDING"
orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && pnpm build"

echo "$MSG_CMD_UPDATE_UI"
orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && pnpm ui:build"

echo "$MSG_CMD_UPDATE_REINSTALL"
orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && sudo npm install -g ."

# Auto-detect sandbox Dockerfile changes
OLD_HASH=$(orb -m "$OPENCLAW_VM_NAME" bash -lc "cat ~/.openclaw/.sandbox-build-hash 2>/dev/null || echo none")
NEW_HASH=$(orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && cat Dockerfile.sandbox Dockerfile.sandbox-browser scripts/sandbox-setup.sh scripts/sandbox-common-setup.sh scripts/sandbox-browser-setup.sh 2>/dev/null | sha256sum | cut -d' ' -f1")
if [ "$OLD_HASH" != "$NEW_HASH" ]; then
    SANDBOX=true
    echo "$MSG_CMD_UPDATE_SANDBOX_CHANGED"
fi

if [ "$SANDBOX" = true ]; then
    echo "$MSG_CMD_UPDATE_SANDBOX_REBUILD"
    echo "$MSG_CMD_UPDATE_SANDBOX_BASE"
    orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && sg docker -c './scripts/sandbox-setup.sh'" 2>/dev/null || true
    echo "$MSG_CMD_UPDATE_SANDBOX_COMMON"
    orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && sg docker -c './scripts/sandbox-common-setup.sh'" 2>/dev/null || true
    echo "$MSG_CMD_UPDATE_SANDBOX_BROWSER"
    orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && sg docker -c './scripts/sandbox-browser-setup.sh'" 2>/dev/null || true
    echo "$MSG_CMD_UPDATE_SANDBOX_NOTE"
    # Save new sandbox build hash
    orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && cat Dockerfile.sandbox Dockerfile.sandbox-browser scripts/sandbox-setup.sh scripts/sandbox-common-setup.sh scripts/sandbox-browser-setup.sh 2>/dev/null | sha256sum | cut -d' ' -f1 > ~/.openclaw/.sandbox-build-hash"
fi

echo "$MSG_CMD_UPDATE_STARTING"
orb -m "$OPENCLAW_VM_NAME" bash -lc "openclaw gateway start"

echo "$MSG_CMD_UPDATE_DONE"
if [ "$SANDBOX" = false ]; then
    echo "$MSG_CMD_UPDATE_SANDBOX_HINT"
fi
