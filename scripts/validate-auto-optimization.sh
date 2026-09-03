#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOTFIX="$ROOT/scripts/mechos-auto-optimization-hotfix.sh"
PATCHER="$ROOT/scripts/patch-mechos-reference-v5.py"

fail(){ echo "[validate-auto-optimization] ERROR: $*" >&2; exit 1; }

[ -f "$HOTFIX" ] || fail "auto optimization hotfix missing"
[ -f "$PATCHER" ] || fail "Reference v5 patcher missing"

bash -n "$HOTFIX" || fail "auto optimization hotfix shell syntax failed"
grep -Fq 'MECHOS_AUTO_OPTIMIZATION_V2' "$HOTFIX" || fail "runtime marker missing"
grep -Fq 'systemd-detect-virt' "$HOTFIX" || fail "virtualization detection missing"
grep -Fq "candidates=['balanced','power-saver'] if virtual else ['performance','balanced','power-saver']" "$HOTFIX" || fail "profile fallback policy missing"
grep -Fq 'lambda:mechos_auto_optimize(self)' "$HOTFIX" || fail "Auto Optimization action is not rewired"
grep -Fq 'mechos-auto-optimization-hotfix.sh' "$PATCHER" || fail "hotfix is not wired into the final build chain"

echo '[validate-auto-optimization] OK: Auto Optimization is VM/hardware aware and build-wired'
