#!/bin/bash
# Shared loader for openclaw command scripts
# Sources VM name and language strings
# Usage: source "$(dirname "$0")/_common.sh"

set -e

# Resolve repo root (scripts/commands/ -> repo root)
OPENCLAW_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=../lib/common.sh
source "$OPENCLAW_REPO_DIR/scripts/lib/common.sh"

# Dynamic VM_NAME resolution (not hardcoded at generation time)
resolve_vm_name

# Language loading
_OPENCLAW_LANG="en"
if [ -f "$HOME/bin/.openclaw-lang" ]; then
    # shellcheck disable=SC1091
    source "$HOME/bin/.openclaw-lang"
    _OPENCLAW_LANG="${OPENCLAW_LANG:-en}"
fi

load_lang_file "$OPENCLAW_REPO_DIR" "$_OPENCLAW_LANG"
