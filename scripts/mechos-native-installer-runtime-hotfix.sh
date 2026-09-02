#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
HELPER="$ROOT/usr/local/libexec/mechos-native-install-helper"

log() { printf '[MechOS Native Installer Hotfix] %s\n' "$*"; }
fail() { printf '[MechOS Native Installer Hotfix] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$PHASE" = "final" ] || exit 0
[ -f "$HELPER" ] || fail "native installer helper is missing"

# GROUPS is a Bash special variable. Never use it for the temporary OOBE group
# list or some shells will reject/ignore the assignment at installation time.
sed -i \
  -e 's/^  GROUPS=/  SETUP_GROUPS=/' \
  -e 's/\$GROUPS/\$SETUP_GROUPS/g' \
  "$HELPER"

bash -n "$HELPER" || fail "native installer helper syntax failed after runtime hotfix"
grep -Fq 'SETUP_GROUPS=' "$HELPER" || fail "safe setup group variable is missing"
if grep -Eq '^[[:space:]]*GROUPS=' "$HELPER"; then
  fail "reserved Bash GROUPS variable is still assigned"
fi

log "native installer setup-user variables hardened"
