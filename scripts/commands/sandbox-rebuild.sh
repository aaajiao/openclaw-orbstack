#!/bin/bash
# openclaw-sandbox-rebuild: Rebuild sandbox Docker images
# Called via thin wrapper: ~/bin/openclaw-sandbox-rebuild -> this script

# shellcheck source=_common.sh
source "$(dirname "$0")/_common.sh"

for arg in "$@"; do
    case "$arg" in
        --help|-h)
            echo "$MSG_CMD_REBUILD_USAGE"
            echo ""
            echo "$MSG_CMD_REBUILD_DESC"
            exit 0
            ;;
        *)
            echo "$MSG_CMD_REBUILD_USAGE"
            exit 1
            ;;
    esac
done

echo "$MSG_CMD_REBUILD_START"
BASE_OK=false
COMMON_OK=false
BROWSER_OK=false

echo "$MSG_CMD_REBUILD_BASE"
_t0=$(date +%s)
_rc=0
sandbox_build base .rebuild-sandbox-base.log || _rc=$?
if [ "$_rc" -eq 0 ]; then
    BASE_OK=true
    printf '%s (%s)\n' "$MSG_CMD_REBUILD_BASE_OK" "$(fmt_elapsed "$(($(date +%s) - _t0))")"
elif [ "$_rc" -eq 2 ]; then
    BASE_OK=true
    printf '%s (%s)\n' "$MSG_CMD_REBUILD_BASE_OK_DF" "$(fmt_elapsed "$(($(date +%s) - _t0))")"
else
    echo "$MSG_CMD_REBUILD_BASE_FAIL"
    vm_log_tail ".rebuild-sandbox-base.log"
fi

# Skip common if base failed (common depends on base)
if [ "$BASE_OK" = true ]; then
    echo "$MSG_CMD_REBUILD_COMMON"
    _t0=$(date +%s)
    _rc=0
    sandbox_build common .rebuild-sandbox-common.log || _rc=$?
    if [ "$_rc" -eq 0 ]; then
        COMMON_OK=true
        printf '%s (%s)\n' "$MSG_CMD_REBUILD_COMMON_OK" "$(fmt_elapsed "$(($(date +%s) - _t0))")"
    else
        echo "$MSG_CMD_REBUILD_COMMON_FAIL"
        vm_log_tail ".rebuild-sandbox-common.log"
    fi
else
    echo "$MSG_CMD_REBUILD_COMMON_SKIP"
fi

echo "$MSG_CMD_REBUILD_BROWSER"
_t0=$(date +%s)
_rc=0
sandbox_build browser .rebuild-sandbox-browser.log || _rc=$?
if [ "$_rc" -eq 0 ]; then
    BROWSER_OK=true
    printf '%s (%s)\n' "$MSG_CMD_REBUILD_BROWSER_OK" "$(fmt_elapsed "$(($(date +%s) - _t0))")"
elif [ "$_rc" -eq 2 ]; then
    BROWSER_OK=true
    printf '%s (%s)\n' "$MSG_CMD_REBUILD_BROWSER_OK_DF" "$(fmt_elapsed "$(($(date +%s) - _t0))")"
else
    echo "$MSG_CMD_REBUILD_BROWSER_FAIL"
    vm_log_tail ".rebuild-sandbox-browser.log"
fi

# Clean up old monolithic hash file
vm_exec "rm -f ~/.openclaw/.sandbox-build-hash" 2>/dev/null || true

if [ "$BASE_OK" = false ] || [ "$COMMON_OK" = false ] || [ "$BROWSER_OK" = false ]; then
    echo "$MSG_CMD_REBUILD_PARTIAL"
fi

echo ""
echo "$MSG_CMD_REBUILD_DONE"
echo "$MSG_CMD_REBUILD_NOTE"
