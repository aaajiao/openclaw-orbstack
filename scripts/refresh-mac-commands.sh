#!/bin/bash
set -e

# Regenerate Mac ~/bin/openclaw-* convenience commands
# For existing users to update command scripts (does not affect VM or sandbox)
#
# Usage:
#   cd openclaw-orbstack && git pull && bash scripts/refresh-mac-commands.sh

# --- Language Selection ---
# Resolve project root reliably (works with bash script.sh, ./script.sh, absolute path, etc.)
_SELF="${BASH_SOURCE[0]:-$0}"
_SELF_DIR="$(cd "$(dirname "$_SELF")" && pwd)"
SCRIPT_DIR="$(cd "$_SELF_DIR/.." && pwd)"

select_language() {
    # If explicitly set via env var, skip interactive prompt
    if [ -n "$OPENCLAW_LANG" ]; then
        echo "$OPENCLAW_LANG"
        return
    fi

    echo "" >&2
    echo "Choose language / 选择语言:" >&2
    echo "" >&2
    echo "  1) English" >&2
    echo "  2) 中文" >&2
    echo "" >&2
    while true; do
        read -rp "Enter 1 or 2 / 输入 1 或 2: " choice
        case "$choice" in
            1) echo "en"; return ;;
            2) echo "zh-CN"; return ;;
            *) echo "  Invalid choice / 无效选择, please enter 1 or 2 / 请输入 1 或 2" >&2 ;;
        esac
    done
}

OPENCLAW_LANG_CODE=$(select_language)
LANG_FILE="$SCRIPT_DIR/lang/${OPENCLAW_LANG_CODE}.sh"

if [ -f "$LANG_FILE" ]; then
    # shellcheck source=../lang/en.sh
    source "$LANG_FILE"
else
    echo "Warning: Language file $LANG_FILE not found, falling back to English"
    source "$SCRIPT_DIR/lang/en.sh"
fi

echo "$MSG_REFRESH_START"

# Load VM name from saved config or use default
VM_NAME="${OPENCLAW_VM_NAME:-openclaw-vm}"
if [ -f "$HOME/bin/.openclaw-vm" ]; then
    # shellcheck disable=SC1091
    source "$HOME/bin/.openclaw-vm"
    VM_NAME="${OPENCLAW_VM:-$VM_NAME}"
fi

mkdir -p ~/bin

# Save language preference and VM name
cat > ~/bin/.openclaw-lang << LANG_EOF
OPENCLAW_LANG=$OPENCLAW_LANG_CODE
LANG_EOF

cat > ~/bin/.openclaw-vm << VM_EOF
OPENCLAW_VM=$VM_NAME
VM_EOF

cat > ~/bin/openclaw-status << EOF
#!/bin/bash
set -e
orb -m "$VM_NAME" bash -lc "openclaw gateway status"
EOF

cat > ~/bin/openclaw-logs << EOF
#!/bin/bash
set -e
orb -m "$VM_NAME" bash -lc "openclaw logs --follow"
EOF

cat > ~/bin/openclaw-restart << EOF
#!/bin/bash
set -e
orb -m "$VM_NAME" bash -lc "openclaw gateway restart"
EOF

cat > ~/bin/openclaw-stop << EOF
#!/bin/bash
set -e
orb -m "$VM_NAME" bash -lc "openclaw gateway stop"
EOF

cat > ~/bin/openclaw-start << EOF
#!/bin/bash
set -e
orb -m "$VM_NAME" bash -lc "openclaw gateway start"
EOF

cat > ~/bin/openclaw-shell << EOF
#!/bin/bash
orb -m "$VM_NAME"
EOF

cat > ~/bin/openclaw << EOF
#!/bin/bash
set -e
if [ \$# -eq 0 ]; then
    set -- "--help"
fi
ARGS=\$(printf '%q ' "\$@")
orb -m "$VM_NAME" bash -lc "openclaw \$ARGS"
EOF

# --- Helper: load language for commands ---
_LANG_LOADER='
# Load language
_OPENCLAW_LANG="en"
if [ -f "$HOME/bin/.openclaw-lang" ]; then source "$HOME/bin/.openclaw-lang"; _OPENCLAW_LANG="${OPENCLAW_LANG:-en}"; fi
_SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")/.." && pwd)"
_LANG_FILE=""
for _d in "$_SCRIPT_DIR/lang" "/usr/local/share/openclaw/lang" "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")/../lang"; do
    if [ -f "$_d/${_OPENCLAW_LANG}.sh" ]; then _LANG_FILE="$_d/${_OPENCLAW_LANG}.sh"; break; fi
done
if [ -n "$_LANG_FILE" ]; then source "$_LANG_FILE"; fi
'

cat > ~/bin/openclaw-config << CMDEOF
#!/bin/bash
$_LANG_LOADER
ACTION="\${1:-edit}"

case "\$ACTION" in
    edit)
        echo "\$MSG_CMD_CONFIG_OPENING"
        orb -m $VM_NAME bash -lc "nano ~/.openclaw/openclaw.json 2>/dev/null || vi ~/.openclaw/openclaw.json"
        echo "\$MSG_CMD_CONFIG_SAVED"
        ;;
    show)
        orb -m $VM_NAME bash -lc "cat ~/.openclaw/openclaw.json"
        ;;
    backup)
        BACKUP="openclaw-config-\$(date +%Y%m%d-%H%M%S).json"
        orb -m $VM_NAME bash -lc "cat ~/.openclaw/openclaw.json" > "\$BACKUP"
        printf "\$MSG_CMD_CONFIG_BACKED_UP\n" "\$BACKUP"
        ;;
    *)
        echo "\$MSG_CMD_CONFIG_USAGE"
        ;;
esac
CMDEOF

cat > ~/bin/openclaw-update << CMDEOF
#!/bin/bash
set -e
$_LANG_LOADER

SANDBOX=false
for arg in "\$@"; do
    case "\$arg" in
        --sandbox) SANDBOX=true ;;
        --help|-h)
            echo "\$MSG_CMD_UPDATE_USAGE"
            echo ""
            echo "\$MSG_CMD_UPDATE_DESC"
            echo ""
            echo "\$MSG_CMD_UPDATE_OPTIONS"
            echo "\$MSG_CMD_UPDATE_SANDBOX_OPT"
            echo ""
            echo "\$MSG_CMD_UPDATE_TIP"
            exit 0
            ;;
    esac
done

# Auto-detect stale system-level service and self-repair
if grep -q "systemctl status openclaw" ~/bin/openclaw-status 2>/dev/null; then
    echo "\$MSG_UPDATE_AUTO_UPGRADE"
    # VM: migrate from system-level to user-level service
    orb -m $VM_NAME bash -lc "sudo systemctl stop openclaw 2>/dev/null || true"
    orb -m $VM_NAME bash -lc "sudo systemctl disable openclaw 2>/dev/null || true"
    orb -m $VM_NAME bash -lc "sudo rm -f /etc/systemd/system/openclaw.service && sudo systemctl daemon-reload"
    orb -m $VM_NAME bash -lc "sudo loginctl enable-linger \\\$(whoami)"
    orb -m $VM_NAME bash -lc "systemctl --user enable openclaw-gateway.service 2>/dev/null || true"
    # Mac: fix stale commands
    cat > ~/bin/openclaw-status << 'FIXEOF'
#!/bin/bash
orb -m $VM_NAME bash -lc "openclaw gateway status"
FIXEOF
    cat > ~/bin/openclaw-logs << 'FIXEOF'
#!/bin/bash
orb -m $VM_NAME bash -lc "openclaw logs --follow"
FIXEOF
    cat > ~/bin/openclaw-restart << 'FIXEOF'
#!/bin/bash
orb -m $VM_NAME bash -lc "openclaw gateway restart"
FIXEOF
    cat > ~/bin/openclaw-stop << 'FIXEOF'
#!/bin/bash
orb -m $VM_NAME bash -lc "openclaw gateway stop"
FIXEOF
    cat > ~/bin/openclaw-start << 'FIXEOF'
#!/bin/bash
orb -m $VM_NAME bash -lc "openclaw gateway start"
FIXEOF
    chmod +x ~/bin/openclaw-status ~/bin/openclaw-logs ~/bin/openclaw-restart ~/bin/openclaw-stop ~/bin/openclaw-start
    echo "\$MSG_UPDATE_AUTO_UPGRADE_DONE"
fi

# Ensure .env exists with at least Bonjour vars
if ! orb -m $VM_NAME bash -lc 'test -f ~/.openclaw/.env' 2>/dev/null; then
    orb -m $VM_NAME bash -lc 'mkdir -p ~/.openclaw && printf "# OpenClaw Environment Variables\nOPENCLAW_DISABLE_BONJOUR=1\nCLAWDBOT_DISABLE_BONJOUR=1\n" > ~/.openclaw/.env && chmod 600 ~/.openclaw/.env'
    echo "  \$MSG_UPDATE_ENV_CREATED"
fi

echo "\$MSG_CMD_UPDATE_UPDATING"

echo "\$MSG_CMD_UPDATE_STOPPING"
orb -m $VM_NAME bash -lc "openclaw gateway stop"

echo "\$MSG_CMD_UPDATE_PULLING"
orb -m $VM_NAME bash -lc "cd ~/openclaw && git fetch --tags"
LATEST_TAG=\$(orb -m $VM_NAME bash -lc "cd ~/openclaw && git describe --tags \\\$(git rev-list --tags --max-count=1)")
echo "  -> \$LATEST_TAG"
orb -m $VM_NAME bash -lc "cd ~/openclaw && git checkout '\$LATEST_TAG'"

echo "\$MSG_CMD_UPDATE_INSTALLING"
orb -m $VM_NAME bash -lc "cd ~/openclaw && pnpm install"

echo "\$MSG_CMD_UPDATE_BUILDING"
orb -m $VM_NAME bash -lc "cd ~/openclaw && pnpm build"

echo "\$MSG_CMD_UPDATE_UI"
orb -m $VM_NAME bash -lc "cd ~/openclaw && pnpm ui:build"

echo "\$MSG_CMD_UPDATE_REINSTALL"
orb -m $VM_NAME bash -lc "cd ~/openclaw && sudo npm install -g ."

# Auto-detect sandbox Dockerfile changes
OLD_HASH=\$(orb -m $VM_NAME bash -lc "cat ~/.openclaw/.sandbox-build-hash 2>/dev/null || echo none")
NEW_HASH=\$(orb -m $VM_NAME bash -lc "cd ~/openclaw && cat Dockerfile.sandbox Dockerfile.sandbox-browser scripts/sandbox-setup.sh scripts/sandbox-common-setup.sh scripts/sandbox-browser-setup.sh 2>/dev/null | sha256sum | cut -d' ' -f1")
if [ "\$OLD_HASH" != "\$NEW_HASH" ]; then
    SANDBOX=true
    echo "\$MSG_CMD_UPDATE_SANDBOX_CHANGED"
fi

if [ "\$SANDBOX" = true ]; then
    echo "\$MSG_CMD_UPDATE_SANDBOX_REBUILD"
    echo "\$MSG_CMD_UPDATE_SANDBOX_BASE"
    orb -m $VM_NAME bash -lc "cd ~/openclaw && sg docker -c './scripts/sandbox-setup.sh'" 2>/dev/null || true
    echo "\$MSG_CMD_UPDATE_SANDBOX_COMMON"
    orb -m $VM_NAME bash -lc "cd ~/openclaw && sg docker -c './scripts/sandbox-common-setup.sh'" 2>/dev/null || true
    echo "\$MSG_CMD_UPDATE_SANDBOX_BROWSER"
    orb -m $VM_NAME bash -lc "cd ~/openclaw && sg docker -c './scripts/sandbox-browser-setup.sh'" 2>/dev/null || true
    echo "\$MSG_CMD_UPDATE_SANDBOX_NOTE"
    # Save new sandbox build hash
    orb -m $VM_NAME bash -lc "cd ~/openclaw && cat Dockerfile.sandbox Dockerfile.sandbox-browser scripts/sandbox-setup.sh scripts/sandbox-common-setup.sh scripts/sandbox-browser-setup.sh 2>/dev/null | sha256sum | cut -d' ' -f1 > ~/.openclaw/.sandbox-build-hash"
fi

echo "\$MSG_CMD_UPDATE_STARTING"
orb -m $VM_NAME bash -lc "openclaw gateway start"

echo "\$MSG_CMD_UPDATE_DONE"
if [ "\$SANDBOX" = false ]; then
    echo "\$MSG_CMD_UPDATE_SANDBOX_HINT"
fi
CMDEOF

cat > ~/bin/openclaw-sandbox-rebuild << CMDEOF
#!/bin/bash
set -e
$_LANG_LOADER

echo "\$MSG_CMD_REBUILD_START"

echo "\$MSG_CMD_REBUILD_BASE"
if orb -m $VM_NAME bash -lc "cd ~/openclaw && sg docker -c './scripts/sandbox-setup.sh'" 2>/dev/null; then
    echo "\$MSG_CMD_REBUILD_BASE_OK"
elif orb -m $VM_NAME bash -lc "cd ~/openclaw && sg docker -c 'docker build -t openclaw-sandbox:bookworm-slim -f Dockerfile.sandbox .'" 2>/dev/null; then
    echo "\$MSG_CMD_REBUILD_BASE_OK_DF"
else
    echo "\$MSG_CMD_REBUILD_BASE_FAIL"
fi

echo "\$MSG_CMD_REBUILD_COMMON"
if orb -m $VM_NAME bash -lc "cd ~/openclaw && sg docker -c './scripts/sandbox-common-setup.sh'" 2>/dev/null; then
    echo "\$MSG_CMD_REBUILD_COMMON_OK"
else
    echo "\$MSG_CMD_REBUILD_COMMON_FAIL"
fi

echo "\$MSG_CMD_REBUILD_BROWSER"
if orb -m $VM_NAME bash -lc "cd ~/openclaw && sg docker -c './scripts/sandbox-browser-setup.sh'" 2>/dev/null; then
    echo "\$MSG_CMD_REBUILD_BROWSER_OK"
elif orb -m $VM_NAME bash -lc "cd ~/openclaw && sg docker -c 'docker build -t openclaw-sandbox-browser:bookworm-slim -f Dockerfile.sandbox-browser .'" 2>/dev/null; then
    echo "\$MSG_CMD_REBUILD_BROWSER_OK_DF"
else
    echo "\$MSG_CMD_REBUILD_BROWSER_FAIL"
fi

# Save new sandbox build hash
orb -m $VM_NAME bash -lc "cd ~/openclaw && cat Dockerfile.sandbox Dockerfile.sandbox-browser scripts/sandbox-setup.sh scripts/sandbox-common-setup.sh scripts/sandbox-browser-setup.sh 2>/dev/null | sha256sum | cut -d' ' -f1 > ~/.openclaw/.sandbox-build-hash"

echo ""
echo "\$MSG_CMD_REBUILD_DONE"
echo "\$MSG_CMD_REBUILD_NOTE"
CMDEOF

cat > ~/bin/openclaw-telegram << CMDEOF
#!/bin/bash
$_LANG_LOADER
ACTION="\${1:-help}"

case "\$ACTION" in
    add)
        if [ -z "\$2" ]; then
            echo "\$MSG_CMD_TG_ADD_USAGE"
            echo "\$MSG_CMD_TG_ADD_HINT"
            exit 1
        fi
        orb -m $VM_NAME bash -lc "openclaw channels add --channel telegram --token \$(printf '%q' "\$2")"
        ;;
    approve)
        if [ -z "\$2" ]; then
            echo "\$MSG_CMD_TG_APPROVE_USAGE"
            echo "\$MSG_CMD_TG_APPROVE_HINT"
            exit 1
        fi
        orb -m $VM_NAME bash -lc "openclaw pairing approve telegram \$(printf '%q' "\$2")"
        ;;
    *)
        echo "\$MSG_CMD_TG_TITLE"
        echo ""
        echo "\$MSG_CMD_TG_USAGE"
        echo "\$MSG_CMD_TG_ADD_DESC"
        echo "\$MSG_CMD_TG_APPROVE_DESC"
        echo ""
        echo "\$MSG_CMD_TG_ALT"
        echo "\$MSG_CMD_TG_ALT_CMD"
        ;;
esac
CMDEOF

cat > ~/bin/openclaw-doctor << EOF
#!/bin/bash
set -e
ARGS=\$(printf '%q ' "\$@")
orb -m "$VM_NAME" bash -lc "openclaw doctor \$ARGS"
EOF

cat > ~/bin/openclaw-whatsapp << EOF
#!/bin/bash
set -e
orb -m "$VM_NAME" bash -lc "openclaw channels login --channel whatsapp"
EOF

chmod +x ~/bin/openclaw-*
chmod +x ~/bin/openclaw

echo "$MSG_REFRESH_DONE"
echo ""
echo "$MSG_REFRESH_LIST_HEADER"
echo "$MSG_REFRESH_CMD_CLI"
echo "$MSG_REFRESH_CMD_STATUS"
echo "$MSG_REFRESH_CMD_LOGS"
echo "$MSG_REFRESH_CMD_RESTART"
echo "$MSG_REFRESH_CMD_STARTSTOP"
echo "$MSG_REFRESH_CMD_SHELL"
echo "$MSG_REFRESH_CMD_CONFIG"
echo "$MSG_REFRESH_CMD_UPDATE"
echo "$MSG_REFRESH_CMD_REBUILD"
echo "$MSG_REFRESH_CMD_DOCTOR"
echo "$MSG_REFRESH_CMD_TELEGRAM"
echo "$MSG_REFRESH_CMD_WHATSAPP"
echo ""
echo "$MSG_REFRESH_PATH_HINT"
