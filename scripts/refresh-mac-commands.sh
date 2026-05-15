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

# Save language preference, VM name, and repo path
cat > ~/bin/.openclaw-lang << LANG_EOF
OPENCLAW_LANG=$OPENCLAW_LANG_CODE
LANG_EOF

cat > ~/bin/.openclaw-vm << VM_EOF
OPENCLAW_VM=$VM_NAME
VM_EOF

# Save repo path so thin wrappers can find scripts/commands/
echo "$SCRIPT_DIR" > ~/bin/.openclaw-repo

# --- Simple commands (inline, use runtime VM_NAME resolution) ---
# These are short enough to never need updating via repo

# Helper: inline VM resolution snippet (3 lines, embedded in simple commands)
_VM_RESOLVE='_VM="openclaw-vm"; [ -f "$HOME/bin/.openclaw-vm" ] && source "$HOME/bin/.openclaw-vm" && _VM="${OPENCLAW_VM:-$_VM}"'

cat > ~/bin/openclaw-status << EOF
#!/bin/bash
set -e
$_VM_RESOLVE
orb -m "\$_VM" bash -lc "openclaw gateway status"
EOF

cat > ~/bin/openclaw-logs << EOF
#!/bin/bash
set -e
$_VM_RESOLVE
orb -m "\$_VM" bash -lc "openclaw logs --follow"
EOF

cat > ~/bin/openclaw-restart << EOF
#!/bin/bash
set -e
$_VM_RESOLVE
orb -m "\$_VM" bash -lc "openclaw gateway restart"
EOF

cat > ~/bin/openclaw-stop << EOF
#!/bin/bash
set -e
$_VM_RESOLVE
orb -m "\$_VM" bash -lc "openclaw gateway stop"
EOF

cat > ~/bin/openclaw-start << EOF
#!/bin/bash
set -e
$_VM_RESOLVE
orb -m "\$_VM" bash -lc "openclaw gateway start"
EOF

cat > ~/bin/openclaw-shell << EOF
#!/bin/bash
$_VM_RESOLVE
orb -m "\$_VM"
EOF

cat > ~/bin/openclaw << EOF
#!/bin/bash
set -e
$_VM_RESOLVE
if [ \$# -eq 0 ]; then
    set -- "--help"
fi
ARGS=\$(printf '%q ' "\$@")
orb -m "\$_VM" bash -lc "openclaw \$ARGS"
EOF

cat > ~/bin/openclaw-doctor << EOF
#!/bin/bash
set -e
$_VM_RESOLVE
ARGS=\$(printf '%q ' "\$@")
orb -m "\$_VM" bash -lc "openclaw doctor \$ARGS"
EOF

cat > ~/bin/openclaw-whatsapp << EOF
#!/bin/bash
set -e
$_VM_RESOLVE
orb -m "\$_VM" bash -lc "openclaw channels login --channel whatsapp"
EOF

# openclaw-codex-login: device-code OAuth for ChatGPT subscription.
# VM is headless (no browser), so we use --device-auth: codex prints a
# verification URL + user code, the user opens that URL in their Mac browser
# and enters the code. codex polls and writes the token to ~/.codex/auth.json
# inside the VM. OpenClaw v2026.5.14+ (PR #82117) reads from that file as a
# runtime fallback when its own openai-codex OAuth refresh fails.
# We use `orb run` (not `bash -lc`) so the codex TTY stays interactive and
# the user can see the verification URL/code live.
cat > ~/bin/openclaw-codex-login << EOF
#!/bin/bash
set -e
$_VM_RESOLVE
if ! orb -m "\$_VM" bash -lc 'command -v codex >/dev/null 2>&1'; then
    echo "Codex CLI is not installed in the VM. Run openclaw-update to install it."
    exit 1
fi
exec orb -m "\$_VM" codex login --device-auth "\$@"
EOF

# --- Complex commands (thin wrappers -> scripts/commands/) ---
# These delegate to repo scripts so they auto-update on next openclaw-update

cat > ~/bin/openclaw-update << 'CMDEOF'
#!/bin/bash
set -e
REPO=$(cat ~/bin/.openclaw-repo 2>/dev/null)
if [ -z "$REPO" ] || [ ! -d "$REPO" ]; then
    echo "Error: openclaw-orbstack repo not found. Run: cd openclaw-orbstack && git pull && bash scripts/refresh-mac-commands.sh"
    exit 1
fi
# Self-update: pull latest openclaw-orbstack repo before executing
cd "$REPO" && git pull -q 2>/dev/null || echo "⚠ Failed to update openclaw-orbstack repo, using cached version"
exec bash "$REPO/scripts/commands/update.sh" "$@"
CMDEOF

cat > ~/bin/openclaw-config << 'CMDEOF'
#!/bin/bash
set -e
REPO=$(cat ~/bin/.openclaw-repo 2>/dev/null)
if [ -z "$REPO" ] || [ ! -d "$REPO" ]; then
    echo "Error: openclaw-orbstack repo not found. Run: cd openclaw-orbstack && git pull && bash scripts/refresh-mac-commands.sh"
    exit 1
fi
exec bash "$REPO/scripts/commands/config.sh" "$@"
CMDEOF

cat > ~/bin/openclaw-telegram << 'CMDEOF'
#!/bin/bash
set -e
REPO=$(cat ~/bin/.openclaw-repo 2>/dev/null)
if [ -z "$REPO" ] || [ ! -d "$REPO" ]; then
    echo "Error: openclaw-orbstack repo not found. Run: cd openclaw-orbstack && git pull && bash scripts/refresh-mac-commands.sh"
    exit 1
fi
exec bash "$REPO/scripts/commands/telegram.sh" "$@"
CMDEOF

cat > ~/bin/openclaw-sandbox-rebuild << 'CMDEOF'
#!/bin/bash
set -e
REPO=$(cat ~/bin/.openclaw-repo 2>/dev/null)
if [ -z "$REPO" ] || [ ! -d "$REPO" ]; then
    echo "Error: openclaw-orbstack repo not found. Run: cd openclaw-orbstack && git pull && bash scripts/refresh-mac-commands.sh"
    exit 1
fi
exec bash "$REPO/scripts/commands/sandbox-rebuild.sh" "$@"
CMDEOF

cat > ~/bin/openclaw-uninstall << 'CMDEOF'
#!/bin/bash
set -e
REPO=$(cat ~/bin/.openclaw-repo 2>/dev/null)
if [ -z "$REPO" ] || [ ! -d "$REPO" ]; then
    echo "Error: openclaw-orbstack repo not found. Run: cd openclaw-orbstack && bash scripts/commands/uninstall.sh"
    exit 1
fi
exec bash "$REPO/scripts/commands/uninstall.sh" "$@"
CMDEOF

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
echo "$MSG_REFRESH_CMD_CODEX_LOGIN"
echo "$MSG_REFRESH_CMD_UNINSTALL"
echo ""
# Auto-add ~/bin to PATH in shell rc (same logic as setup script)
if ! echo "$PATH" | grep -q "$HOME/bin"; then
    _SHELL_NAME=$(basename "${SHELL:-/bin/bash}")
    case "$_SHELL_NAME" in
        zsh)  _SHELL_RC="$HOME/.zshrc" ;;
        fish) _SHELL_RC="$HOME/.config/fish/config.fish" ;;
        *)    _SHELL_RC="$HOME/.bashrc" ;;
    esac

    if [ "$_SHELL_NAME" = "fish" ]; then
        mkdir -p "$(dirname "$_SHELL_RC")"
        if ! grep -q 'set -gx PATH \$HOME/bin' "$_SHELL_RC" 2>/dev/null; then
            echo '' >> "$_SHELL_RC"
            echo '# OpenClaw CLI' >> "$_SHELL_RC"
            echo 'set -gx PATH $HOME/bin $PATH' >> "$_SHELL_RC"
            echo "$(printf "$MSG_INFO_PATH_ADDED" "$_SHELL_RC")"
        fi
    else
        if ! grep -q 'export PATH="\$HOME/bin:\$PATH"' "$_SHELL_RC" 2>/dev/null; then
            echo '' >> "$_SHELL_RC"
            echo '# OpenClaw CLI' >> "$_SHELL_RC"
            echo 'export PATH="$HOME/bin:$PATH"' >> "$_SHELL_RC"
            echo "$(printf "$MSG_INFO_PATH_ADDED" "$_SHELL_RC")"
        fi
    fi
    echo ""
    echo ">>> $MSG_NOTE_OPEN_NEW_TERMINAL"
fi
