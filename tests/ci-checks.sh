#!/bin/bash
set -e

# ============================================================================
# UX Validation Tests
# Catches i18n gaps, format-string mismatches, and step-numbering errors
# that shellcheck cannot detect.
# Runs on both macOS (BSD grep) and Linux (GNU grep).
# ============================================================================

cd "$(dirname "$0")/.."

FAIL_COUNT=0
LANG_EN="lang/en.sh"
LANG_ZH="lang/zh-CN.sh"
SETUP="openclaw-orbstack-setup.sh"

fail() {
  printf "FAIL: %s\n" "$1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

# Extract MSG_* key names from a lang file (POSIX-compatible)
extract_keys() {
  sed -n 's/^\(MSG_[A-Za-z0-9_]*\)=.*/\1/p' "$1" | sort
}

# ── Check 1: i18n symmetry ─────────────────────────────────────────────────
# en.sh and zh-CN.sh must define exactly the same set of MSG_* keys.
echo "--- Check 1: i18n key symmetry ---"

keys_en=$(extract_keys "$LANG_EN")
keys_zh=$(extract_keys "$LANG_ZH")

only_en=$(comm -23 <(echo "$keys_en") <(echo "$keys_zh"))
only_zh=$(comm -13 <(echo "$keys_en") <(echo "$keys_zh"))

if [[ -n "$only_en" || -n "$only_zh" ]]; then
  [[ -n "$only_en" ]] && fail "Keys in en.sh but missing from zh-CN.sh:
$only_en"
  [[ -n "$only_zh" ]] && fail "Keys in zh-CN.sh but missing from en.sh:
$only_zh"
else
  echo "PASS"
fi

# ── Check 2: i18n reference completeness ───────────────────────────────────
# Every $MSG_* referenced in scripts must be defined in the lang files.
echo "--- Check 2: i18n reference completeness ---"

defined=$(extract_keys "$LANG_EN")

# Collect MSG_* references from all .sh files except lang/ and tests/
refs=$(find . -name '*.sh' \
    -not -path './lang/*' \
    -not -path './tests/*' \
    -not -path '*/.git/*' \
    -exec grep -Eoh '\$\{?MSG_[A-Za-z0-9_]+' {} + \
  | sed 's/[${}]//g' \
  | sort -u)

missing=""
while IFS= read -r ref; do
  [[ -z "$ref" ]] && continue
  if ! echo "$defined" | grep -qx "$ref"; then
    missing+="  $ref"$'\n'
  fi
done <<< "$refs"

if [[ -n "$missing" ]]; then
  fail "MSG_* variables referenced but never defined in $LANG_EN:
$missing"
else
  echo "PASS"
fi

# ── Check 3: printf format-string consistency ──────────────────────────────
# For each MSG_* key, the number of %s placeholders must match across langs.
echo "--- Check 3: printf format-string consistency ---"

fmt_mismatch=""
while IFS= read -r key; do
  [[ -z "$key" ]] && continue
  val_en=$(grep "^${key}=" "$LANG_EN" | head -1 | sed "s/^${key}=//")
  val_zh=$(grep "^${key}=" "$LANG_ZH" | head -1 | sed "s/^${key}=//")
  count_en=$(echo "$val_en" | grep -o '%s' | wc -l | tr -d ' ')
  count_zh=$(echo "$val_zh" | grep -o '%s' | wc -l | tr -d ' ')
  if [[ "$count_en" -ne "$count_zh" ]]; then
    fmt_mismatch+="  $key: en=${count_en} zh=${count_zh}"$'\n'
  fi
done <<< "$keys_en"

if [[ -n "$fmt_mismatch" ]]; then
  fail "printf %%s count mismatch between languages:
$fmt_mismatch"
else
  echo "PASS"
fi

# ── Check 4: step numbering consistency ────────────────────────────────────
# TOTAL_STEPS must equal the number of `step N` calls in setup.sh.
echo "--- Check 4: step numbering consistency ---"

total=$(grep 'TOTAL_STEPS=' "$SETUP" | head -1 | sed 's/.*TOTAL_STEPS=\([0-9]*\).*/\1/')
actual=$(grep -c '^[[:space:]]*step [0-9]' "$SETUP")

if [[ "$total" -ne "$actual" ]]; then
  fail "TOTAL_STEPS=${total} but found ${actual} step calls"
else
  echo "PASS"
fi

# ── Summary ────────────────────────────────────────────────────────────────
echo ""
if [[ "$FAIL_COUNT" -gt 0 ]]; then
  echo "${FAIL_COUNT} check(s) failed."
  exit 1
else
  echo "All checks passed."
fi
