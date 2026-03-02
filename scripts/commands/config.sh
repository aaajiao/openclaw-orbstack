#!/bin/bash
# openclaw-config: Edit/show/backup OpenClaw configuration
# Called via thin wrapper: ~/bin/openclaw-config -> this script

# shellcheck source=_common.sh
source "$(dirname "$0")/_common.sh"

ACTION="${1:-edit}"

case "$ACTION" in
    edit)
        echo "$MSG_CMD_CONFIG_OPENING"
        orb -m "$OPENCLAW_VM_NAME" bash -lc "nano ~/.openclaw/openclaw.json 2>/dev/null || vi ~/.openclaw/openclaw.json"
        echo "$MSG_CMD_CONFIG_SAVED"
        ;;
    show)
        orb -m "$OPENCLAW_VM_NAME" bash -lc "cat ~/.openclaw/openclaw.json"
        ;;
    backup)
        BACKUP="openclaw-config-$(date +%Y%m%d-%H%M%S).json"
        orb -m "$OPENCLAW_VM_NAME" bash -lc "cat ~/.openclaw/openclaw.json" > "$BACKUP"
        # shellcheck disable=SC2059
        printf "$MSG_CMD_CONFIG_BACKED_UP\n" "$BACKUP"
        ;;
    *)
        echo "$MSG_CMD_CONFIG_USAGE"
        ;;
esac
