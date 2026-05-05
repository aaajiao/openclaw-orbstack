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
echo "$MSG_BUILD_PATIENCE"
start_progress
if orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && sg docker -c './scripts/sandbox-setup.sh'" 2>/dev/null; then
    stop_progress
    BASE_OK=true
    echo "$MSG_CMD_REBUILD_BASE_OK"
elif orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && sg docker -c 'DOCKER_BUILDKIT=1 docker build -t openclaw-sandbox:bookworm-slim -f scripts/docker/sandbox/Dockerfile .'" 2>/dev/null; then
    stop_progress
    BASE_OK=true
    echo "$MSG_CMD_REBUILD_BASE_OK_DF"
else
    stop_progress
    echo "$MSG_CMD_REBUILD_BASE_FAIL"
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
    echo "$MSG_BUILD_PATIENCE"
    start_progress
    if orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && sg docker -c './scripts/sandbox-common-setup.sh'" 2>/dev/null; then
        stop_progress
        COMMON_OK=true
        echo "$MSG_CMD_REBUILD_COMMON_OK"
    else
        stop_progress
        echo "$MSG_CMD_REBUILD_COMMON_FAIL"
    fi
else
    echo "$MSG_CMD_REBUILD_COMMON_FAIL"
fi

# Save common hash on success
if [ "$COMMON_OK" = true ]; then
    save_sandbox_hash common scripts/docker/sandbox/Dockerfile.common Dockerfile.sandbox-common scripts/sandbox-common-setup.sh
fi

echo "$MSG_CMD_REBUILD_BROWSER"
echo "$MSG_BUILD_PATIENCE"
start_progress
if orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && sg docker -c './scripts/sandbox-browser-setup.sh'" 2>/dev/null; then
    stop_progress
    BROWSER_OK=true
    echo "$MSG_CMD_REBUILD_BROWSER_OK"
elif orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && sg docker -c 'DOCKER_BUILDKIT=1 docker build -t openclaw-sandbox-browser:bookworm-slim -f scripts/docker/sandbox/Dockerfile.browser .'" 2>/dev/null; then
    stop_progress
    BROWSER_OK=true
    echo "$MSG_CMD_REBUILD_BROWSER_OK_DF"
else
    stop_progress
    echo "$MSG_CMD_REBUILD_BROWSER_FAIL"
fi

# Save browser hash on success
if [ "$BROWSER_OK" = true ]; then
    save_sandbox_hash browser scripts/docker/sandbox/Dockerfile.browser Dockerfile.sandbox-browser scripts/sandbox-browser-setup.sh
fi

# Clean up old monolithic hash file
orb -m "$OPENCLAW_VM_NAME" bash -lc "rm -f ~/.openclaw/.sandbox-build-hash" 2>/dev/null || true

if [ "$BASE_OK" = false ] || [ "$COMMON_OK" = false ] || [ "$BROWSER_OK" = false ]; then
    echo "$MSG_CMD_REBUILD_PARTIAL"
fi

echo ""
echo "$MSG_CMD_REBUILD_DONE"
echo "$MSG_CMD_REBUILD_NOTE"
