#!/bin/bash
# Shared loader for openclaw command scripts
# Sources VM name and language strings
# Usage: source "$(dirname "$0")/_common.sh"

set -e

# --- Progress model: synchronous, newline-only (garble-proof by construction) ---
# The old start_progress/stop_progress printed "\r  <braille> " from a BACKGROUND
# subshell every 0.08s. That second writer raced with any foreground echo /
# streaming orb output on the same TTY → interleaved on one line = "花屏" (screen
# garble). It is removed: with no async writer and no carriage returns anywhere,
# garble is impossible in TTY, pipe, log, and over the orb transport — not merely
# improbable. Each long step now prints a plain start line, runs FULLY redirected
# to a per-step log inside the VM, then prints its existing ✓/✗ result line (with
# elapsed) and, on failure, the real error tail read back from the VM log.
#
# start_progress/stop_progress are kept as no-op stubs so any stray/未迁移 call
# site is harmless (calling an undefined function would abort under `set -e`).
start_progress() { :; }
stop_progress() { :; }

# Lines of a failing step's VM-side log to surface inline (the real error).
OPENCLAW_LOG_TAIL_LINES="${OPENCLAW_LOG_TAIL_LINES:-12}"

# fmt_elapsed <seconds> -> "Xm Ys" or "Ys"  (BSD/macOS integer math only)
fmt_elapsed() {
    if [ "$1" -ge 60 ]; then
        printf '%dm %ds' "$(($1 / 60))" "$(($1 % 60))"
    else
        printf '%ds' "$1"
    fi
}

# vm_log_tail <log-basename>
#   On a step failure, surface the real cause: tail the last
#   $OPENCLAW_LOG_TAIL_LINES of a log that lives INSIDE the VM at
#   ~/.openclaw/<basename> (read via orb — a Mac-side tail would hit the wrong
#   filesystem), strip any stray \r the tool wrote, indent, then print the
#   full-log hint. Never aborts (set -e safe). Pass just the basename:
#     vm_log_tail ".update-sandbox-base.log"
vm_log_tail() {
    printf '    %s\n' "$MSG_LOG_TAIL_HEADER"
    # \$HOME is escaped so the VM shell (not the Mac) expands it — avoids a literal
    # ~ in quotes (SC2088) while still resolving the VM home correctly.
    orb -m "$OPENCLAW_VM_NAME" bash -lc "tail -n $OPENCLAW_LOG_TAIL_LINES \"\$HOME/.openclaw/$1\" 2>/dev/null | tr -d '\r'" 2>/dev/null | sed 's/^/      /' || true
    # ~ is intentional display text the user types; %s is the basename.
    # shellcheck disable=SC2059,SC2088
    printf "$MSG_LOG_FULL_HINT\n" "~/.openclaw/$1"
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
