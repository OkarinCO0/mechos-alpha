#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
HELPER="$ROOT/usr/local/libexec/mechos-native-install-helper"
PHASE2="/workspace/scripts/mechos-phase2-optimization-integration.sh"

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

# Phase 2 must run here, after the native installer helper exists. This lets it
# switch new installs from the graphical-target firstboot service to the
# non-blocking post-graphical timer while also patching the installed payload.
[ -f "$PHASE2" ] || fail "Phase 2 optimization integration is missing"
bash "$PHASE2" final

log "native installer setup-user variables hardened and Phase 2 optimization applied"
