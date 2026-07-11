#!/bin/bash
# openclaw-telegram: Telegram Bot management
# Called via thin wrapper: ~/bin/openclaw-telegram -> this script

# shellcheck source=_common.sh
source "$(dirname "$0")/_common.sh"

ACTION="${1:-help}"

case "$ACTION" in
    add)
        TOKEN="$2"
        if [ -z "$TOKEN" ]; then
            # No token on argv (keeps it out of Mac shell history) - prompt with hidden input.
            read -rsp "$MSG_CMD_TG_TOKEN_PROMPT" TOKEN
            echo ""
            if [ -z "$TOKEN" ]; then
                echo "$MSG_CMD_TG_ADD_USAGE"
                echo "$MSG_CMD_TG_ADD_HINT"
                exit 1
            fi
        fi
        orb -m "$OPENCLAW_VM_NAME" bash -lc "openclaw channels add --channel telegram --token $(printf '%q' "$TOKEN")"
        ;;
    approve)
        CODE="$2"
        if [ -z "$CODE" ]; then
            read -rp "$MSG_CMD_TG_CODE_PROMPT" CODE
            if [ -z "$CODE" ]; then
                echo "$MSG_CMD_TG_APPROVE_USAGE"
                echo "$MSG_CMD_TG_APPROVE_HINT"
                exit 1
            fi
        fi
        orb -m "$OPENCLAW_VM_NAME" bash -lc "openclaw pairing approve telegram $(printf '%q' "$CODE")"
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
