#!/bin/bash
# openclaw-telegram: Telegram Bot management
# Called via thin wrapper: ~/bin/openclaw-telegram -> this script

# shellcheck source=_common.sh
source "$(dirname "$0")/_common.sh"

ACTION="${1:-help}"

case "$ACTION" in
    add)
        if [ -z "$2" ]; then
            echo "$MSG_CMD_TG_ADD_USAGE"
            echo "$MSG_CMD_TG_ADD_HINT"
            exit 1
        fi
        orb -m "$OPENCLAW_VM_NAME" bash -lc "openclaw channels add --channel telegram --token $(printf '%q' "$2")"
        ;;
    approve)
        if [ -z "$2" ]; then
            echo "$MSG_CMD_TG_APPROVE_USAGE"
            echo "$MSG_CMD_TG_APPROVE_HINT"
            exit 1
        fi
        orb -m "$OPENCLAW_VM_NAME" bash -lc "openclaw pairing approve telegram $(printf '%q' "$2")"
        ;;
    *)
        echo "$MSG_CMD_TG_TITLE"
        echo ""
        echo "$MSG_CMD_TG_USAGE"
        echo "$MSG_CMD_TG_ADD_DESC"
        echo "$MSG_CMD_TG_APPROVE_DESC"
        echo ""
        echo "$MSG_CMD_TG_ALT"
        echo "$MSG_CMD_TG_ALT_CMD"
        ;;
esac
