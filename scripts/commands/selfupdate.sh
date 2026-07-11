#!/bin/bash
# openclaw-selfupdate: Update the openclaw-orbstack WRAPPER (this repo) to a
# release-pinned tag.
#
# This is DISTINCT from openclaw-update, which updates upstream OpenClaw inside
# the VM. openclaw-selfupdate runs entirely on the Mac host and only touches the
# local repo clone + regenerates the ~/bin/openclaw-* wrappers. It never talks to
# the VM.
#
# Called via thin wrapper: ~/bin/openclaw-selfupdate -> this script

# SC1091: Dynamic source of _common.sh
# shellcheck disable=SC1091
source "$(dirname "$0")/_common.sh"

PRE=false
TARGET_VERSION=""
for arg in "$@"; do
    case "$arg" in
        --pre) PRE=true ;;
        --version=*) TARGET_VERSION="${arg#--version=}" ;;
        --help|-h)
            echo "$MSG_CMD_SELFUPDATE_USAGE"
            echo ""
            echo "$MSG_CMD_SELFUPDATE_DESC"
            echo ""
            echo "$MSG_CMD_UPDATE_OPTIONS"
            echo "$MSG_CMD_SELFUPDATE_PRE_OPT"
            echo "$MSG_CMD_SELFUPDATE_VERSION_OPT"
            echo ""
            echo "$MSG_CMD_SELFUPDATE_TIP"
            exit 0
            ;;
        *)
            # Unknown flag or bare arg (e.g. the space form `--version v...`,
            # which does not match the `--version=*` glob). Fail loudly instead
            # of silently falling through to the default latest-stable path.
            # shellcheck disable=SC2059
            printf "$MSG_CMD_SELFUPDATE_UNKNOWN_OPT\n" "$arg"
            echo "$MSG_CMD_SELFUPDATE_USAGE"
            exit 1
            ;;
    esac
done

# Operate on the repo clone (resolved by _common.sh, not hardcoded).
if ! cd "$OPENCLAW_REPO_DIR"; then
    echo "$MSG_CMD_SELFUPDATE_NO_REPO"
    exit 1
fi

# Record current wrapper version before doing anything.
OLD_VERSION=$(git describe --tags --always 2>/dev/null || echo "unknown")

# Mirror update.sh's fetch hygiene (--force --prune tolerate rewritten refs).
echo "$MSG_CMD_SELFUPDATE_FETCHING"
git fetch --tags --quiet --force --prune 2>/dev/null || true

# --- Determine the TARGET tag ------------------------------------------------
if [ -n "$TARGET_VERSION" ]; then
    # Explicit pin: verify the tag exists (allows rollback to any tag).
    if ! git rev-parse --verify "$TARGET_VERSION^{commit}" >/dev/null 2>&1; then
        # shellcheck disable=SC2059
        printf "$MSG_ERR_VERSION_NOT_FOUND\n" "$TARGET_VERSION"
        exit 1
    fi
    TARGET_TAG="$TARGET_VERSION"
    # shellcheck disable=SC2059
    printf "$MSG_CMD_SELFUPDATE_VERSION_USING\n" "$TARGET_TAG"
elif [ "$PRE" = true ]; then
    # Newest tag overall (includes pre-releases). sort -V is NOT semver-prerelease-
    # aware — it ranks `X.Y.Z-beta.N` ABOVE `X.Y.Z`, the opposite of semver. Translate
    # the semver `-` separator to `~` (which GNU/Apple sort -V both order BEFORE the
    # release) so a stable release outranks its own prerelease, then translate back.
    TARGET_TAG=$(git tag -l 'v*' | sed 's/-/~/g' | sort -V | tail -1 | sed 's/~/-/g')
else
    # Latest NON-prerelease tag (same filter openclaw-update uses for stable).
    TARGET_TAG=$(git tag -l 'v*' | grep -v -e '-beta' -e '-rc' -e '-alpha' | sort -V | tail -1)
fi

if [ -z "$TARGET_TAG" ]; then
    echo "$MSG_ERR_NO_VERSION"
    exit 1
fi

# --- Never downgrade (default and --pre only) --------------------------------
# If the target commit is already an ancestor of HEAD, the current checkout
# already includes it -> no-op. This makes a branch user who is AHEAD of the
# latest stable tag a safe no-op on the default path, and lets --pre still move
# them onto a newer pre-release tag. --version= is EXEMPT (explicit rollback).
if [ -z "$TARGET_VERSION" ]; then
    if git merge-base --is-ancestor "$TARGET_TAG" HEAD 2>/dev/null; then
        # shellcheck disable=SC2059
        printf "$MSG_CMD_SELFUPDATE_ALREADY\n" "$TARGET_TAG"
        exit 0
    fi
fi

# --- Check out the pinned tag (detached HEAD is intended) --------------------
# refresh-mac-commands.sh skips its silent self-update pull when HEAD is detached,
# so the wrapper regeneration below will NOT undo this checkout.
# shellcheck disable=SC2059
printf "$MSG_CMD_SELFUPDATE_CHECKOUT\n" "$TARGET_TAG"
if ! git -c advice.detachedHead=false checkout -q "$TARGET_TAG" 2>/dev/null; then
    # shellcheck disable=SC2059
    printf "$MSG_CMD_SELFUPDATE_CHECKOUT_FAIL\n" "$TARGET_TAG"
    exit 1
fi

# Regenerate ~/bin/openclaw-* from the checked-out tag. Pass through language +
# VM name like update.sh does so refresh-mac-commands.sh stays non-interactive.
OPENCLAW_LANG="$_OPENCLAW_LANG" OPENCLAW_VM_NAME="$OPENCLAW_VM_NAME" \
    bash "$OPENCLAW_REPO_DIR/scripts/refresh-mac-commands.sh" 2>/dev/null || true

NEW_VERSION=$(git describe --tags --always 2>/dev/null || echo "unknown")
# shellcheck disable=SC2059
printf "$MSG_CMD_SELFUPDATE_DONE\n" "$OLD_VERSION" "$NEW_VERSION"
