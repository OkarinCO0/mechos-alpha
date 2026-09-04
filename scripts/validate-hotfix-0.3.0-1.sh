#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT/scripts/mechos-hotfix-0.3.0-1-apply.sh"
fail(){ echo "[validate-hotfix-0.3.0-1] ERROR: $*" >&2; exit 1; }

[ -f "$HELPER" ] || fail "Hotfix 1 apply helper missing"
bash -n "$HELPER" || fail "Hotfix 1 apply helper shell syntax failed"
grep -Fq 'MECHOS_VM_MODE_RUNTIME_ROUTER_V1' "$HELPER" || fail "VM controller router repair missing"
grep -Fq 'MECHOS_VM_PLASMA_HOST_V2' "$HELPER" || fail "VM MechScope session repair missing"
grep -Fq 'MECHOS_REFERENCE_SPLASH_V1' "$HELPER" || fail "reference Plymouth theme repair missing"
grep -Fq 'mkinitcpio -P' "$HELPER" || fail "initramfs rebuild missing"
grep -Fq 'quiet splash' "$HELPER" || fail "kernel splash options repair missing"
grep -Fq 'hotfix-0.3.0-1-applied' "$HELPER" || fail "one-time completion marker missing"

echo '[validate-hotfix-0.3.0-1] OK: Hotfix 1 can repair VM mode routing and installed Plymouth state once after Update Center installation'
