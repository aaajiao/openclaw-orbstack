#!/bin/bash
set -e

# Regenerate Mac ~/bin/openclaw-* convenience commands
# For existing users to update command scripts (does not affect VM or sandbox)
#
# Usage:
#   cd openclaw-orbstack && git pull && bash scripts/refresh-mac-commands.sh
#
# GENERATOR vs GENERATED: this script itself may source scripts/lib/common.sh
# for shared helpers (select_language / load_lang_file / resolve_vm_name /
# append_path_to_shell_rc). Every file it WRITES under ~/bin, however, must
# stay fully standalone at runtime (no lib dependency, no repo dependency
# except the two thin-wrapper dispatch targets) — those files are copied to
# the user's ~/bin and must keep working even if the repo checkout moves or
# scripts/lib/common.sh changes shape later.

# --- Resolve project root reliably (works with bash script.sh, ./script.sh, absolute path, etc.) ---
_SELF="${BASH_SOURCE[0]:-$0}"
_SELF_DIR="$(cd "$(dirname "$_SELF")" && pwd)"
SCRIPT_DIR="$(cd "$_SELF_DIR/.." && pwd)"

# shellcheck source=lib/common.sh
source "$_SELF_DIR/lib/common.sh"

# --- Language Selection ---
OPENCLAW_LANG_CODE=$(select_language)
load_lang_file "$SCRIPT_DIR" "$OPENCLAW_LANG_CODE"

echo "$MSG_REFRESH_START"

# Load VM name from saved config or use default
resolve_vm_name
VM_NAME="$OPENCLAW_VM_NAME"

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

# Helper: inline VM resolution snippet (3 lines, embedded in every generated file)
_VM_RESOLVE='_VM="openclaw-vm"; [ -f "$HOME/bin/.openclaw-vm" ] && source "$HOME/bin/.openclaw-vm" && _VM="${OPENCLAW_VM:-$_VM}"'

# gen_deprecation_notice <cmd_name> <replacement_text>
#   Prints (to be captured into a generated file) one stderr line warning that
#   this ~/bin/openclaw-<cmd_name> is a deprecated alias. English only — same
#   standalone-generated-file exception as the rest of these command bodies.
gen_deprecation_notice() {
    printf 'echo "[deprecated] openclaw-%s: use '\''%s'\'' (this alias still works)" >&2\n' "$1" "$2"
}

# --- Table: simple VM-command wrappers ---
# Fields: name|vm_command|deprecated(yes/no)|replacement_text|forward_args(yes/no)
# forward_args=yes means the wrapper forwards "$@" via printf %q (only doctor today).
SIMPLE_CMDS=(
    "status|openclaw gateway status|no||no"
    "logs|openclaw logs --follow|no||no"
    "restart|openclaw gateway restart|no||no"
    "stop|openclaw gateway stop|yes|openclaw gateway stop|no"
    "start|openclaw gateway start|yes|openclaw gateway start|no"
    "whatsapp|openclaw channels login --channel whatsapp|yes|openclaw channels login --channel whatsapp|no"
    "doctor|openclaw doctor|yes|openclaw doctor [args]|yes"
)

for _entry in "${SIMPLE_CMDS[@]}"; do
    IFS='|' read -r _name _vmcmd _deprecated _replacement _forward <<< "$_entry"
    _out="$HOME/bin/openclaw-$_name"
    {
        echo '#!/bin/bash'
        echo 'set -e'
        echo "$_VM_RESOLVE"
        if [ "$_deprecated" = "yes" ]; then
            gen_deprecation_notice "$_name" "$_replacement"
        fi
        if [ "$_forward" = "yes" ]; then
            echo 'ARGS=$(printf '\''%q '\'' "$@")'
            printf 'orb -m "$_VM" bash -lc "%s $ARGS"\n' "$_vmcmd"
        else
            printf 'orb -m "$_VM" bash -lc "%s"\n' "$_vmcmd"
        fi
    } > "$_out"
done

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

# openclaw-codex-login: device-code OAuth for ChatGPT subscription.
# VM is headless (no browser), so we use --device-auth: codex prints a
# verification URL + user code, the user opens that URL in their Mac browser
# and enters the code. codex polls and writes the token to ~/.codex/auth.json
# inside the VM. OpenClaw v2026.5.14+ (PR #82117) reads from that file as a
# runtime fallback when its own openai OAuth refresh fails (provider 旧名 openai-codex，
# v2026.6.1 doctor 起统一改名为 openai).
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

# --- Table: dispatch wrappers -> $REPO/scripts/commands/<name>.sh ---
# Fields: name|deprecated(yes/no)|replacement_text
DISPATCH_CMDS=(
    "update|no|"
    "selfupdate|no|"
    "config|no|"
    "telegram|yes|openclaw channels add --channel telegram --token <token> / openclaw pairing approve telegram <code>"
    "sandbox-rebuild|no|"
    "uninstall|no|"
)

for _entry in "${DISPATCH_CMDS[@]}"; do
    IFS='|' read -r _name _deprecated _replacement <<< "$_entry"
    _out="$HOME/bin/openclaw-$_name"
    {
        echo '#!/bin/bash'
        echo 'set -e'
        echo 'REPO=$(cat ~/bin/.openclaw-repo 2>/dev/null)'
        echo 'if [ -z "$REPO" ] || [ ! -d "$REPO" ]; then'
        echo '    echo "Error: openclaw-orbstack repo not found. Run: cd openclaw-orbstack && git pull && bash scripts/refresh-mac-commands.sh"'
        echo '    exit 1'
        echo 'fi'
        if [ "$_name" = "update" ]; then
            cat <<'BLOCK'
# Self-update: pull latest openclaw-orbstack repo before executing — but ONLY
# when HEAD is on a BRANCH. A detached HEAD means the user pinned a release tag
# via openclaw-selfupdate; leave it pinned (no pull, no warning) so branch users
# and selfupdate-pinned users coexist.
#
# DEFERRED CUTOVER: the full switch — removing this auto-pull entirely and making
# openclaw-selfupdate the default wrapper-delivery path — is deferred to the
# v2026.7.1 stable /sync-upstream, when a STABLE tag will finally carry the
# openclaw-selfupdate command. Cutting over now would strand users: the current
# latest stable tag (v2026.6.11) predates openclaw-selfupdate.
if git -C "$REPO" symbolic-ref -q HEAD >/dev/null 2>&1; then
    (cd "$REPO" && git pull -q 2>/dev/null) || echo "⚠ Failed to update openclaw-orbstack repo, using cached version"
fi
BLOCK
        fi
        if [ "$_deprecated" = "yes" ]; then
            gen_deprecation_notice "$_name" "$_replacement"
        fi
        printf 'exec bash "$REPO/scripts/commands/%s.sh" "$@"\n' "$_name"
    } > "$_out"
done

chmod +x ~/bin/openclaw-*
chmod +x ~/bin/openclaw

echo "$MSG_REFRESH_DONE"
echo ""
echo "$MSG_REFRESH_LIST_HEADER"
echo "$MSG_REFRESH_CMD_CLI"
echo "$MSG_REFRESH_CMD_STATUS"
echo "$MSG_REFRESH_CMD_LOGS"
echo "$MSG_REFRESH_CMD_RESTART"
echo "$MSG_REFRESH_CMD_SHELL"
echo "$MSG_REFRESH_CMD_CONFIG"
echo "$MSG_REFRESH_CMD_UPDATE"
echo "$MSG_REFRESH_CMD_SELFUPDATE"
echo "$MSG_REFRESH_CMD_REBUILD"
echo "$MSG_REFRESH_CMD_CODEX_LOGIN"
echo "$MSG_REFRESH_CMD_UNINSTALL"
echo "$MSG_REFRESH_DEPRECATED_NOTE"
echo ""
# Auto-add ~/bin to PATH in shell rc (same logic as setup script)
if append_path_to_shell_rc; then
    echo "$(printf "$MSG_INFO_PATH_ADDED" "$OPENCLAW_SHELL_RC")"
    echo ""
    echo ">>> $MSG_NOTE_OPEN_NEW_TERMINAL"
fi
