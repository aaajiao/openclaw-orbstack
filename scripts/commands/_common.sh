#!/bin/bash
# Shared loader for openclaw command scripts
# Sources VM name and language strings
# Usage: source "$(dirname "$0")/_common.sh"

set -e

# Progress spinner for long-running commands (braille animation)
_progress_pid=""
_progress_flag=""
start_progress() {
    _progress_flag="$(mktemp)"
    (
        trap 'exit 0' TERM
        frames="⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏"
        while [ -e "$_progress_flag" ]; do
            for f in $frames; do
                [ -e "$_progress_flag" ] || break
                printf "\r  %s " "$f"
                sleep 0.08
            done
        done
    ) &
    _progress_pid=$!
}
stop_progress() {
    if [ -n "$_progress_flag" ]; then
        rm -f "$_progress_flag"
        _progress_flag=""
    fi
    if [ -n "$_progress_pid" ]; then
        kill "$_progress_pid" 2>/dev/null || true
        wait "$_progress_pid" 2>/dev/null || true
        _progress_pid=""
        printf "\r    \r"
    fi
}

# Resolve repo root (scripts/commands/ -> repo root)
OPENCLAW_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Dynamic VM_NAME resolution (not hardcoded at generation time)
OPENCLAW_VM_NAME="${OPENCLAW_VM_NAME:-openclaw-vm}"
if [ -f "$HOME/bin/.openclaw-vm" ]; then
    # shellcheck disable=SC1091
    source "$HOME/bin/.openclaw-vm"
    OPENCLAW_VM_NAME="${OPENCLAW_VM:-$OPENCLAW_VM_NAME}"
fi

# Language loading
_OPENCLAW_LANG="en"
if [ -f "$HOME/bin/.openclaw-lang" ]; then
    # shellcheck disable=SC1091
    source "$HOME/bin/.openclaw-lang"
    _OPENCLAW_LANG="${OPENCLAW_LANG:-en}"
fi
# Save per-image sandbox build hash on VM
# Usage: save_sandbox_hash <image_name> <file1> [file2 ...]
save_sandbox_hash() {
    local name="$1"; shift
    orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && cat $* 2>/dev/null | sha256sum | cut -c1-64 > ~/.openclaw/.sandbox-hash-$name"
}

_LANG_FILE="$OPENCLAW_REPO_DIR/lang/${_OPENCLAW_LANG}.sh"
if [ -f "$_LANG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$_LANG_FILE"
else
    # Fallback to English
    # shellcheck disable=SC1091
    source "$OPENCLAW_REPO_DIR/lang/en.sh"
fi
