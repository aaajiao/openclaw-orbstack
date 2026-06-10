#!/bin/bash
# openclaw-sandbox-rebuild: Rebuild sandbox Docker images
# Called via thin wrapper: ~/bin/openclaw-sandbox-rebuild -> this script

# shellcheck source=_common.sh
source "$(dirname "$0")/_common.sh"

echo "$MSG_CMD_REBUILD_START"
BASE_OK=false
COMMON_OK=false
BROWSER_OK=false

echo "$MSG_CMD_REBUILD_BASE"
_t0=$(date +%s)
if vm_exec "cd ~/openclaw && sg docker -c './scripts/sandbox-setup.sh' > ~/.openclaw/.rebuild-sandbox-base.log 2>&1"; then
    BASE_OK=true
    printf '%s (%s)\n' "$MSG_CMD_REBUILD_BASE_OK" "$(fmt_elapsed "$(($(date +%s) - _t0))")"
elif vm_exec "cd ~/openclaw && sg docker -c 'DOCKER_BUILDKIT=1 docker build -t openclaw-sandbox:bookworm-slim -f scripts/docker/sandbox/Dockerfile .' >> ~/.openclaw/.rebuild-sandbox-base.log 2>&1"; then
    BASE_OK=true
    printf '%s (%s)\n' "$MSG_CMD_REBUILD_BASE_OK_DF" "$(fmt_elapsed "$(($(date +%s) - _t0))")"
else
    echo "$MSG_CMD_REBUILD_BASE_FAIL"
    vm_log_tail ".rebuild-sandbox-base.log"
fi

# Save base hash on success.
# Lists both new (≥ v2026.5.3 scripts/docker/sandbox/) and legacy (≤ v2026.5.2 root) paths;
# cat skips missing files via 2>/dev/null in the helper, so the hash reflects the actual
# upstream layout.
if [ "$BASE_OK" = true ]; then
    save_sandbox_hash base scripts/docker/sandbox/Dockerfile Dockerfile.sandbox scripts/sandbox-setup.sh
fi

# Skip common if base failed (common depends on base)
if [ "$BASE_OK" = true ]; then
    echo "$MSG_CMD_REBUILD_COMMON"
    _t0=$(date +%s)
    if vm_exec "cd ~/openclaw && sg docker -c './scripts/sandbox-common-setup.sh' > ~/.openclaw/.rebuild-sandbox-common.log 2>&1"; then
        COMMON_OK=true
        printf '%s (%s)\n' "$MSG_CMD_REBUILD_COMMON_OK" "$(fmt_elapsed "$(($(date +%s) - _t0))")"
    else
        echo "$MSG_CMD_REBUILD_COMMON_FAIL"
        vm_log_tail ".rebuild-sandbox-common.log"
    fi
else
    echo "$MSG_CMD_REBUILD_COMMON_FAIL"
fi

# Save common hash on success
if [ "$COMMON_OK" = true ]; then
    save_sandbox_hash common scripts/docker/sandbox/Dockerfile.common Dockerfile.sandbox-common scripts/sandbox-common-setup.sh
fi

echo "$MSG_CMD_REBUILD_BROWSER"
_t0=$(date +%s)
if vm_exec "cd ~/openclaw && sg docker -c './scripts/sandbox-browser-setup.sh' > ~/.openclaw/.rebuild-sandbox-browser.log 2>&1"; then
    BROWSER_OK=true
    printf '%s (%s)\n' "$MSG_CMD_REBUILD_BROWSER_OK" "$(fmt_elapsed "$(($(date +%s) - _t0))")"
elif vm_exec "cd ~/openclaw && sg docker -c 'DOCKER_BUILDKIT=1 docker build -t openclaw-sandbox-browser:bookworm-slim -f scripts/docker/sandbox/Dockerfile.browser .' >> ~/.openclaw/.rebuild-sandbox-browser.log 2>&1"; then
    BROWSER_OK=true
    printf '%s (%s)\n' "$MSG_CMD_REBUILD_BROWSER_OK_DF" "$(fmt_elapsed "$(($(date +%s) - _t0))")"
else
    echo "$MSG_CMD_REBUILD_BROWSER_FAIL"
    vm_log_tail ".rebuild-sandbox-browser.log"
fi

# Save browser hash on success
if [ "$BROWSER_OK" = true ]; then
    save_sandbox_hash browser scripts/docker/sandbox/Dockerfile.browser Dockerfile.sandbox-browser scripts/sandbox-browser-setup.sh
fi

# Clean up old monolithic hash file
vm_exec "rm -f ~/.openclaw/.sandbox-build-hash" 2>/dev/null || true

if [ "$BASE_OK" = false ] || [ "$COMMON_OK" = false ] || [ "$BROWSER_OK" = false ]; then
    echo "$MSG_CMD_REBUILD_PARTIAL"
fi

echo ""
echo "$MSG_CMD_REBUILD_DONE"
echo "$MSG_CMD_REBUILD_NOTE"
