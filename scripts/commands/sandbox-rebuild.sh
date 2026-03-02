#!/bin/bash
# openclaw-sandbox-rebuild: Rebuild sandbox Docker images
# Called via thin wrapper: ~/bin/openclaw-sandbox-rebuild -> this script

# shellcheck source=_common.sh
source "$(dirname "$0")/_common.sh"

echo "$MSG_CMD_REBUILD_START"

echo "$MSG_CMD_REBUILD_BASE"
if orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && sg docker -c './scripts/sandbox-setup.sh'" 2>/dev/null; then
    echo "$MSG_CMD_REBUILD_BASE_OK"
elif orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && sg docker -c 'docker build -t openclaw-sandbox:bookworm-slim -f Dockerfile.sandbox .'" 2>/dev/null; then
    echo "$MSG_CMD_REBUILD_BASE_OK_DF"
else
    echo "$MSG_CMD_REBUILD_BASE_FAIL"
fi

echo "$MSG_CMD_REBUILD_COMMON"
if orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && sg docker -c './scripts/sandbox-common-setup.sh'" 2>/dev/null; then
    echo "$MSG_CMD_REBUILD_COMMON_OK"
else
    echo "$MSG_CMD_REBUILD_COMMON_FAIL"
fi

echo "$MSG_CMD_REBUILD_BROWSER"
if orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && sg docker -c './scripts/sandbox-browser-setup.sh'" 2>/dev/null; then
    echo "$MSG_CMD_REBUILD_BROWSER_OK"
elif orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && sg docker -c 'docker build -t openclaw-sandbox-browser:bookworm-slim -f Dockerfile.sandbox-browser .'" 2>/dev/null; then
    echo "$MSG_CMD_REBUILD_BROWSER_OK_DF"
else
    echo "$MSG_CMD_REBUILD_BROWSER_FAIL"
fi

# Save new sandbox build hash
orb -m "$OPENCLAW_VM_NAME" bash -lc "cd ~/openclaw && cat Dockerfile.sandbox Dockerfile.sandbox-browser scripts/sandbox-setup.sh scripts/sandbox-common-setup.sh scripts/sandbox-browser-setup.sh 2>/dev/null | sha256sum | cut -d' ' -f1 > ~/.openclaw/.sandbox-build-hash"

echo ""
echo "$MSG_CMD_REBUILD_DONE"
echo "$MSG_CMD_REBUILD_NOTE"
