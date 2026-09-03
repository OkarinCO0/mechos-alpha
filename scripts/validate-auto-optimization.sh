#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOTFIX="$ROOT/scripts/mechos-auto-optimization-hotfix.sh"
PATCHER="$ROOT/scripts/patch-mechos-reference-v5.py"

fail(){ echo "[validate-auto-optimization] ERROR: $*" >&2; exit 1; }

[ -f "$HOTFIX" ] || fail "auto optimization hotfix missing"
[ -f "$PATCHER" ] || fail "Reference v5 patcher missing"

bash -n "$HOTFIX" || fail "auto optimization hotfix shell syntax failed"
grep -Fq 'MECHOS_AUTO_OPTIMIZATION_V3' "$HOTFIX" || fail "runtime marker missing"
grep -Fq 'systemd-detect-virt' "$HOTFIX" || fail "virtualization detection missing"
grep -Fq "candidates=['balanced','power-saver'] if virtual else ['performance','balanced','power-saver']" "$HOTFIX" || fail "profile fallback policy missing"
grep -Fq 'ast.parse' "$HOTFIX" || fail "structural Python action discovery missing"
grep -Fq 'ast.get_source_segment' "$HOTFIX" || fail "structural action replacement missing"
grep -Fq "{'Auto Optimization','Optimize Now'}" "$HOTFIX" || fail "optimization action labels are not structurally targeted"
grep -Fq 'lambda:mechos_auto_optimize(self)' "$HOTFIX" || fail "Auto Optimization action is not rewired"
if grep -Fq 'old="self.action' "$HOTFIX"; then
  fail "stale exact-string Auto Optimization patching returned"
fi
grep -Fq 'mechos-auto-optimization-hotfix.sh' "$PATCHER" || fail "hotfix is not wired into the final build chain"

echo '[validate-auto-optimization] OK: Auto Optimization uses structural action discovery and VM/hardware-aware profile selection'
