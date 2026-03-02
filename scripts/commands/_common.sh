#!/bin/bash
# Shared loader for openclaw command scripts
# Sources VM name and language strings
# Usage: source "$(dirname "$0")/_common.sh"

set -e

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
_LANG_FILE="$OPENCLAW_REPO_DIR/lang/${_OPENCLAW_LANG}.sh"
if [ -f "$_LANG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$_LANG_FILE"
else
    # Fallback to English
    # shellcheck disable=SC1091
    source "$OPENCLAW_REPO_DIR/lang/en.sh"
fi
