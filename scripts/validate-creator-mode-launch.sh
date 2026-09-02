#!/usr/bin/env bash
set -Eeuo pipefail

BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HOTFIX="$BASE/scripts/mechos-creator-mode-launch-hotfix.sh"
PATCHER="$BASE/scripts/patch-mechos-safe-mode-switching.py"
BUILDER="$BASE/scripts/build-mechos-archiso.sh"

fail() { echo "Creator Mode launch validation error: $*" >&2; exit 1; }

[ -f "$HOTFIX" ] || fail "Creator Mode launch hotfix is missing"
[ -f "$PATCHER" ] || fail "mode-switch patcher is missing"
[ -f "$BUILDER" ] || fail "ArchISO builder is missing"

bash -n "$HOTFIX" || fail "Creator Mode launch hotfix shell syntax failed"
python3 -m py_compile "$PATCHER" || fail "mode-switch patcher Python syntax failed"

grep -Fq 'ExecStart=/usr/local/bin/mechos-creator-mode' "$HOTFIX" \
  || fail "Creator Mode does not have its own systemd user service"
grep -Fq 'systemctl --user start --no-block mechos-creator-mode.service' "$HOTFIX" \
  || fail "Creator Mode is not launched through the independent user service"
grep -Fq 'mechos-creator-mode-launch-hotfix.sh final' "$PATCHER" \
  || fail "Creator Mode launch hotfix is not wired into mode-switch integration"

# Make sure the mode-switch patcher remains idempotent and inserts one launch fix.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp "$BUILDER" "$tmp/builder.sh"
python3 "$PATCHER" "$tmp/builder.sh" >/dev/null
first="$(sha256sum "$tmp/builder.sh" | awk '{print $1}')"
python3 "$PATCHER" "$tmp/builder.sh" >/dev/null
second="$(sha256sum "$tmp/builder.sh" | awk '{print $1}')"
[ "$first" = "$second" ] || fail "mode-switch patcher is not idempotent"
[ "$(grep -c 'mechos-creator-mode-launch-hotfix.sh final' "$tmp/builder.sh")" -eq 1 ] \
  || fail "Creator Mode launch hotfix is missing or duplicated in patched builder"

echo "Creator Mode launch validation passed."
