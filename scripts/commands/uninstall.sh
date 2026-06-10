#!/bin/bash
# Cleanly uninstall OpenClaw OrbStack deployment
#
# Removes: Gateway service, Docker containers/images, config, repo clone,
#          global npm package (inside VM), Mac ~/bin/openclaw-* commands,
#          and optionally the entire VM.
#
# Usage:
#   openclaw-uninstall              # interactive (confirms each step)
#   openclaw-uninstall --yes        # skip confirmations (keeps VM by default)
#   openclaw-uninstall --yes --vm   # skip confirmations and delete VM

# SC1091: Dynamic lang file sourcing
# SC2016: Intentional single-quoted literals ($HOME in grep patterns)
# SC2059: $MSG_* variables are printf format strings by design (i18n)
# shellcheck disable=SC1091,SC2016,SC2059

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "${GREEN}  ✓ $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠ $1${NC}"; }
err()  { echo -e "${RED}  ✗ $1${NC}"; }
info() { echo -e "  $1"; }

# --- Parse flags ---
AUTO_YES=false
DELETE_VM=false
for arg in "$@"; do
    case "$arg" in
        --yes|-y) AUTO_YES=true ;;
        --vm)     DELETE_VM=true ;;
        --help|-h)
            echo "$MSG_CMD_UNINSTALL_USAGE"
            echo ""
            echo "$MSG_CMD_UNINSTALL_DESC"
            echo ""
            echo "$MSG_CMD_UNINSTALL_OPTIONS"
            echo "$MSG_CMD_UNINSTALL_OPT_YES"
            echo "$MSG_CMD_UNINSTALL_OPT_VM"
            exit 0
            ;;
        *)
            echo "$MSG_CMD_UNINSTALL_USAGE"
            exit 1
            ;;
    esac
done

# --- Confirmation helper ---
confirm() {
    if [ "$AUTO_YES" = true ]; then
        return 0
    fi
    local prompt="$1"
    while true; do
        read -rp "  $prompt [y/N] " answer
        case "$answer" in
            [Yy]*) return 0 ;;
            [Nn]*|"") return 1 ;;
        esac
    done
}

# vm_exec is provided by _common.sh (with the OrbStack #2519 stdout-detach guard).

vm_running() {
    orb list 2>/dev/null | grep -F "$OPENCLAW_VM_NAME" | grep -q "running"
}

vm_exists() {
    orb list 2>/dev/null | grep -qF "$OPENCLAW_VM_NAME"
}

# ============================================================================
# Start
# ============================================================================
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}$MSG_CMD_UNINSTALL_TITLE${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "$MSG_CMD_UNINSTALL_WILL_REMOVE"
echo ""
echo "$MSG_CMD_UNINSTALL_VM_ITEMS"
echo "$MSG_CMD_UNINSTALL_VM_1"
echo "$MSG_CMD_UNINSTALL_VM_2"
echo "$MSG_CMD_UNINSTALL_VM_3"
echo "$MSG_CMD_UNINSTALL_VM_4"
echo "$MSG_CMD_UNINSTALL_VM_5"
echo ""
echo "$MSG_CMD_UNINSTALL_MAC_ITEMS"
echo "$MSG_CMD_UNINSTALL_MAC_1"
echo "$MSG_CMD_UNINSTALL_MAC_2"
echo ""

if [ "$AUTO_YES" = false ]; then
    if ! confirm "$MSG_CMD_UNINSTALL_CONFIRM"; then
        echo ""
        echo "$MSG_CMD_UNINSTALL_CANCELLED"
        exit 0
    fi
fi

echo ""

# ============================================================================
# Step 1: Clean up inside VM (if it exists and is reachable)
# ============================================================================
if vm_exists; then
    # Start VM if not running
    if ! vm_running; then
        info "$MSG_CMD_UNINSTALL_STARTING_VM"
        orb start "$OPENCLAW_VM_NAME" 2>/dev/null || true
        sleep 2
    fi

    if vm_exec "true" 2>/dev/null; then
        # 1a. Stop and disable Gateway service
        info "$MSG_CMD_UNINSTALL_STOP_SERVICE"
        vm_exec "openclaw gateway stop 2>/dev/null || true"
        vm_exec "systemctl --user disable openclaw-gateway.service 2>/dev/null || true"
        vm_exec "systemctl --user stop openclaw-gateway.service 2>/dev/null || true"
        # Clean up our systemd drop-in override
        vm_exec "rm -f ~/.config/systemd/user/openclaw-gateway.service.d/openclaw-orbstack.conf 2>/dev/null || true"
        vm_exec "rmdir ~/.config/systemd/user/openclaw-gateway.service.d 2>/dev/null || true"
        ok "$MSG_CMD_UNINSTALL_SERVICE_STOPPED"

        # 1b. Stop and remove Docker containers
        info "$MSG_CMD_UNINSTALL_REMOVE_CONTAINERS"
        vm_exec 'docker ps -aq --filter "name=openclaw-sbx-" 2>/dev/null | xargs -r docker rm -f 2>/dev/null || true'
        ok "$MSG_CMD_UNINSTALL_CONTAINERS_REMOVED"

        # 1c. Remove Docker images
        info "$MSG_CMD_UNINSTALL_REMOVE_IMAGES"
        vm_exec 'docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep "openclaw-sandbox" | xargs -r docker rmi -f 2>/dev/null || true'
        ok "$MSG_CMD_UNINSTALL_IMAGES_REMOVED"

        # 1d. Uninstall global npm package
        info "$MSG_CMD_UNINSTALL_REMOVE_NPM"
        vm_exec "sudo npm uninstall -g openclaw 2>/dev/null || true"
        ok "$MSG_CMD_UNINSTALL_NPM_REMOVED"

        # 1e. Remove config and repo
        info "$MSG_CMD_UNINSTALL_REMOVE_DATA"
        vm_exec "rm -rf ~/.openclaw ~/openclaw"
        ok "$MSG_CMD_UNINSTALL_DATA_REMOVED"
    else
        warn "$MSG_CMD_UNINSTALL_VM_UNREACHABLE"
    fi

    # 1f. Delete VM (optional)
    if [ "$DELETE_VM" = true ] || { [ "$AUTO_YES" = false ] && confirm "$MSG_CMD_UNINSTALL_DELETE_VM"; }; then
        info "$(printf "$MSG_CMD_UNINSTALL_DELETING_VM" "$OPENCLAW_VM_NAME")"
        orb delete "$OPENCLAW_VM_NAME" --force 2>/dev/null || true
        ok "$(printf "$MSG_CMD_UNINSTALL_VM_DELETED" "$OPENCLAW_VM_NAME")"
    else
        info "$MSG_CMD_UNINSTALL_VM_KEPT"
    fi
else
    info "$MSG_CMD_UNINSTALL_NO_VM"
fi

echo ""

# ============================================================================
# Step 2: Clean up Mac host
# ============================================================================
info "$MSG_CMD_UNINSTALL_REMOVE_COMMANDS"

# Remove all openclaw-* commands and openclaw itself
rm -f ~/bin/openclaw ~/bin/openclaw-*
rm -f ~/bin/.openclaw-vm ~/bin/.openclaw-lang ~/bin/.openclaw-repo

# Remove empty ~/bin if we created it
if [ -d ~/bin ] && [ -z "$(ls -A ~/bin 2>/dev/null)" ]; then
    rmdir ~/bin 2>/dev/null || true
fi

ok "$MSG_CMD_UNINSTALL_COMMANDS_REMOVED"

# Remove PATH entry from shell rc
info "$MSG_CMD_UNINSTALL_REMOVE_PATH"

_cleaned=false
for _rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.config/fish/config.fish"; do
    if [ -f "$_rc" ] && grep -q "# OpenClaw CLI" "$_rc" 2>/dev/null; then
        # Remove the comment line and the PATH line that follows it
        # Also remove the blank line before if present
        if [[ "$_rc" == *.fish ]]; then
            grep -v "# OpenClaw CLI" "$_rc" | grep -v 'set -gx PATH \$HOME/bin' > "${_rc}.tmp"
        else
            grep -v "# OpenClaw CLI" "$_rc" | grep -v 'export PATH="\$HOME/bin:\$PATH"' > "${_rc}.tmp"
        fi
        mv "${_rc}.tmp" "$_rc"
        _cleaned=true
        ok "$(printf "$MSG_CMD_UNINSTALL_PATH_CLEANED" "$_rc")"
    fi
done

if [ "$_cleaned" = false ]; then
    info "$MSG_CMD_UNINSTALL_PATH_NONE"
fi

# ============================================================================
# Done
# ============================================================================
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}$MSG_CMD_UNINSTALL_DONE${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "$MSG_CMD_UNINSTALL_DONE_HINT"
echo ""
