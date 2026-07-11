#!/bin/bash
# ============================================================================
# scripts/lib/common.sh — shared Mac-side helpers for openclaw-orbstack
#
# Sourced by: openclaw-orbstack-setup.sh and scripts/commands/_common.sh (which
# scripts/commands/*.sh source in turn). Defines functions/constants ONLY —
# no `set -e` here (callers own that) and nothing runs at source time.
#
# All functions that talk to the VM read $OPENCLAW_VM_NAME. Callers must set
# it before calling vm_exec/vm_log_tail/gateway_healthy/write_systemd_dropins/
# sandbox_build — scripts/commands/_common.sh does this via resolve_vm_name();
# the standalone installer does it by assigning OPENCLAW_VM_NAME="$VM_NAME"
# after computing VM_NAME from the environment.
#
# SC2154: $MSG_* / $OPENCLAW_VM_NAME are defined by callers before/after
# sourcing this file, not in it.
# shellcheck disable=SC2154
# ============================================================================

# --- Progress model: synchronous, newline-only (garble-proof by construction) ---
# The old start_progress/stop_progress printed "\r  <braille> " from a BACKGROUND
# subshell every 0.08s. That second writer raced with any foreground echo /
# streaming orb output on the same TTY -> interleaved on one line = "花屏" (screen
# garble). It is removed: with no async writer and no carriage returns anywhere,
# garble is impossible in TTY, pipe, log, and over the orb transport - not merely
# improbable. Each long step now prints a plain start line, runs FULLY redirected
# to a per-step log inside the VM, then prints its existing ok/fail result line
# (with elapsed) and, on failure, the real error tail read back from the VM log.
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

# resolve_vm_name: sets OPENCLAW_VM_NAME from (in priority order) an already-set
# env var, the persisted ~/bin/.openclaw-vm (written by refresh-mac-commands.sh),
# or the "openclaw-vm" default.
resolve_vm_name() {
    OPENCLAW_VM_NAME="${OPENCLAW_VM_NAME:-openclaw-vm}"
    if [ -f "$HOME/bin/.openclaw-vm" ]; then
        # shellcheck disable=SC1091
        source "$HOME/bin/.openclaw-vm"
        OPENCLAW_VM_NAME="${OPENCLAW_VM:-$OPENCLAW_VM_NAME}"
    fi
}

# vm_exec <script>  — run one non-interactive command inside the VM via orb.
#
# OrbStack #2519: when `orb <cmd>` runs with its Mac-side stdout attached to a
# TTY, orb allocates a PTY and enters the alternate screen buffer; on command
# exit it emits rmcup (ESC[?1049l), which discards the command's output AND homes
# the cursor to the TOP of the terminal ("光标跳到最上方"). It is terminal-agnostic
# (reproduced in Ghostty, Terminal.app, iTerm2) and has no orb flag to disable it.
# The upstream workaround is `orb <cmd> | cat`: detaching stdout from the TTY keeps
# orb in pipe mode — no PTY, no alt-screen, no jump. Redirecting the command INSIDE
# the VM (bash -lc "... > log") does NOT help, because orb's *Mac-side* stdout is
# still the TTY; the redirect has to be on the Mac side.
#
# So: when stdout is a TTY, send orb's Mac-side stdout to /dev/null (stderr stays on
# the TTY so real errors still surface). The `[ -t 1 ]` guard keeps $(vm_exec ...)
# capture working — inside a command substitution fd 1 is a pipe, not a TTY, so the
# else branch runs and stdout flows to the capture. Heavy steps already route their
# real output to a per-step VM log (surfaced by vm_log_tail on failure), so dropping
# the Mac-side stdout of a bare statement loses nothing.
vm_exec() {
    if [ -t 1 ]; then
        orb -m "$OPENCLAW_VM_NAME" bash -lc "$1" >/dev/null
    else
        orb -m "$OPENCLAW_VM_NAME" bash -lc "$1"
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

# select_language: interactive 1/2 prompt (honors $OPENCLAW_LANG to skip it).
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

# load_lang_file <repo_root> <lang_code>
#   Source lang/<lang_code>.sh from the given repo root, falling back to
#   lang/en.sh (with a warning) if the requested file is missing.
load_lang_file() {
    local repo_root="$1" lang_code="$2" lang_file
    lang_file="$repo_root/lang/${lang_code}.sh"
    if [ -f "$lang_file" ]; then
        # shellcheck disable=SC1090
        source "$lang_file"
    else
        echo "Warning: Language file $lang_file not found, falling back to English"
        # shellcheck disable=SC1091
        source "$repo_root/lang/en.sh"
    fi
}

# append_path_to_shell_rc: add "~/bin" to PATH in the user's shell rc file if
# it isn't already on $PATH. Detects zsh/fish/bash and uses the right syntax
# and rc file for each. No-op (returns 1) if ~/bin is already on PATH or the
# rc file already has the line. On success (line appended), sets
# $OPENCLAW_SHELL_RC to the rc file path and returns 0 — callers use that to
# print their own "added to X" message and prompt for a new terminal.
append_path_to_shell_rc() {
    if echo "$PATH" | grep -q "$HOME/bin"; then
        return 1
    fi

    local shell_name shell_rc
    shell_name=$(basename "${SHELL:-/bin/bash}")
    case "$shell_name" in
        zsh)  shell_rc="$HOME/.zshrc" ;;
        fish) shell_rc="$HOME/.config/fish/config.fish" ;;
        *)    shell_rc="$HOME/.bashrc" ;;
    esac

    if [ "$shell_name" = "fish" ]; then
        mkdir -p "$(dirname "$shell_rc")"
        if grep -q 'set -gx PATH \$HOME/bin' "$shell_rc" 2>/dev/null; then
            return 1
        fi
        {
            echo ''
            echo '# OpenClaw CLI'
            echo 'set -gx PATH $HOME/bin $PATH'
        } >> "$shell_rc"
    else
        if grep -q 'export PATH="\$HOME/bin:\$PATH"' "$shell_rc" 2>/dev/null; then
            return 1
        fi
        {
            echo ''
            echo '# OpenClaw CLI'
            echo 'export PATH="$HOME/bin:$PATH"'
        } >> "$shell_rc"
    fi

    # Consumed by callers (e.g. openclaw-orbstack-setup.sh) after this returns.
    # shellcheck disable=SC2034
    OPENCLAW_SHELL_RC="$shell_rc"
    return 0
}

# gateway_healthy: poll up to 6 x 5s for "Runtime: running" inside the VM.
# The single health predicate for gateway readiness — used by the installer
# (initial start) and by openclaw-update (post-update start, and again after
# an auto-repair attempt).
gateway_healthy() {
    # shellcheck disable=SC2016
    vm_exec '
        for _i in $(seq 1 6); do
            openclaw gateway status 2>/dev/null | grep -q "Runtime: running" && exit 0
            if [ "$_i" -lt 6 ]; then sleep 5; fi
        done
        exit 1
    '
}

# write_systemd_dropins: create/refresh the gateway systemd user-service
# drop-ins and daemon-reload. Idempotent — safe to call on every install/update.
#
#   1) openclaw-orbstack.conf — NODE_COMPILE_CACHE + OPENCLAW_NO_RESPAWN bridge
#      (upstream recommended for VM/ARM: docs/vps.md). Bridge pattern: if the
#      main service file already sets NODE_COMPILE_CACHE, upstream has taken
#      over natively — remove our drop-in instead of re-adding it.
#   2) 99-openclaw-orbstack-path.conf — pins a canonical PATH so version-manager
#      / package-manager dirs from the operator's shell (.bun/bin, .npm-global/bin,
#      .nix-profile/bin, .local/share/pnpm) cannot leak into the gateway service
#      PATH (Linux only; upstream #75233 PATH cleanup is macOS LaunchAgent only).
#      systemd evaluates drop-ins after the main unit; the LAST Environment=PATH=
#      wins. The 99- prefix also wins lexicographic ordering against any other
#      drop-ins openclaw or third parties might ship.
#
# Errors are swallowed (best-effort maintenance step, not a hard requirement for
# gateway startup — gateway_healthy is what actually gates success/failure).
write_systemd_dropins() {
    # shellcheck disable=SC2016
    vm_exec '
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

    # shellcheck disable=SC2016
    vm_exec '
DROPIN_DIR=~/.config/systemd/user/openclaw-gateway.service.d
DROPIN=$DROPIN_DIR/99-openclaw-orbstack-path.conf
mkdir -p "$DROPIN_DIR"
printf "[Service]\nEnvironment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n" > "$DROPIN"
systemctl --user daemon-reload
' 2>/dev/null || true
}

# Save per-image sandbox build hash on VM.
# Usage: save_sandbox_hash <image_name> <file1> [file2 ...]
save_sandbox_hash() {
    local name="$1"; shift
    vm_exec "cd ~/openclaw && cat $* 2>/dev/null | sha256sum | cut -c1-64 > ~/.openclaw/.sandbox-hash-$name"
}

# sandbox_build <kind> <log_basename>
#   kind: base | common | browser
#
#   Runs the upstream sandbox setup script for <kind> via `sg docker -c`, with
#   output captured to ~/.openclaw/<log_basename> inside the VM. On failure,
#   for base and browser ONLY, falls back to the direct
#   `DOCKER_BUILDKIT=1 docker build` invocation (appended >> to the same log)
#   — common has no fallback (its setup script is the only build path, as in
#   setup.sh/sandbox-rebuild.sh/update.sh today). On success (either path),
#   saves the per-image hash via save_sandbox_hash.
#
#   Hash inputs list both new (>= v2026.5.3 scripts/docker/sandbox/) and legacy
#   (<= v2026.5.2 repo root) Dockerfile paths; `cat` in save_sandbox_hash skips
#   missing files via 2>/dev/null, so the hash reflects whichever layout the
#   current upstream checkout actually has.
#
#   Returns: 0 = primary (setup script) succeeded
#            2 = fallback (direct docker build) succeeded [base/browser only]
#            1 = failed
#   Prints NOTHING — callers own all messages (their MSG_* keys differ).
sandbox_build() {
    local kind="$1" log="$2"
    local setup_script image_tag dockerfile hash_files

    case "$kind" in
        base)
            setup_script="./scripts/sandbox-setup.sh"
            image_tag="openclaw-sandbox:bookworm-slim"
            dockerfile="scripts/docker/sandbox/Dockerfile"
            hash_files="scripts/docker/sandbox/Dockerfile Dockerfile.sandbox scripts/sandbox-setup.sh"
            ;;
        common)
            setup_script="./scripts/sandbox-common-setup.sh"
            image_tag=""
            dockerfile=""
            hash_files="scripts/docker/sandbox/Dockerfile.common Dockerfile.sandbox-common scripts/sandbox-common-setup.sh"
            ;;
        browser)
            setup_script="./scripts/sandbox-browser-setup.sh"
            image_tag="openclaw-sandbox-browser:bookworm-slim"
            dockerfile="scripts/docker/sandbox/Dockerfile.browser"
            hash_files="scripts/docker/sandbox/Dockerfile.browser Dockerfile.sandbox-browser scripts/sandbox-browser-setup.sh"
            ;;
        *)
            return 1
            ;;
    esac

    if vm_exec "cd ~/openclaw && sg docker -c '$setup_script' > ~/.openclaw/$log 2>&1"; then
        # shellcheck disable=SC2086
        save_sandbox_hash "$kind" $hash_files
        return 0
    fi

    if [ -n "$image_tag" ]; then
        if vm_exec "cd ~/openclaw && sg docker -c 'DOCKER_BUILDKIT=1 docker build -t $image_tag -f $dockerfile .' >> ~/.openclaw/$log 2>&1"; then
            # shellcheck disable=SC2086
            save_sandbox_hash "$kind" $hash_files
            return 2
        fi
    fi

    return 1
}
