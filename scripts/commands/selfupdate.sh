#!/bin/bash
# openclaw-selfupdate: DEPRECATED. Wrapper self-update logic now lives in
# scripts/commands/update.sh's stage 1 — openclaw-update updates both the
# wrapper and OpenClaw in one command. This is a thin compatibility forwarder:
# it prints a deprecation notice, then forwards to `openclaw-update
# --wrapper-only`, which runs stage 1 only (Mac-side, no VM) and exits.
#
# Called via thin wrapper: ~/bin/openclaw-selfupdate -> this script

# SC1091: Dynamic source of _common.sh
# shellcheck disable=SC1091
source "$(dirname "$0")/_common.sh"

echo "$MSG_CMD_SELFUPDATE_DEPRECATED"

# Old flags (--pre / --version=<tag>) pass through and mean the same thing in
# update.sh's stage 1.
exec bash "$(dirname "$0")/update.sh" --wrapper-only "$@"
