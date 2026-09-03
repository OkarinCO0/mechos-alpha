#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOTFIX="$ROOT/scripts/mechos-auto-optimization-hotfix.sh"
PATCHER="$ROOT/scripts/patch-mechos-reference-v5.py"

fail(){ echo "[validate-auto-optimization] ERROR: $*" >&2; exit 1; }

[ -f "$HOTFIX" ] || fail "auto optimization hotfix missing"
[ -f "$PATCHER" ] || fail "Reference v5 patcher missing"

bash -n "$HOTFIX" || fail "auto optimization hotfix shell syntax failed"
grep -Fq 'MECHOS_PROFILE_BACKEND_V5' "$HOTFIX" || fail "hardware-aware backend marker missing"
grep -Fq 'def set_profile(profile, parent=None):' "$HOTFIX" || fail "set_profile backend replacement missing"
grep -Fq 'systemd-detect-virt' "$HOTFIX" || fail "virtualization detection missing"
grep -Fq "['balanced','power-saver'] if virtual else ['performance','balanced','power-saver']" "$HOTFIX" || fail "performance fallback policy missing"
grep -Fq "node.name=='set_profile'" "$HOTFIX" || fail "structural set_profile discovery missing"
grep -Fq 'profile_fn.end_lineno' "$HOTFIX" || fail "structural function replacement missing"
grep -Fq "grep -Fq 'class Perf(' \"\$public\"" "$HOTFIX" || fail "public Performance Center ownership detection missing"
grep -Fq "grep -Fq 'class Perf(' \"\$real\"" "$HOTFIX" || fail ".real fallback ownership detection missing"
if grep -Fq "{'Auto Optimization','Optimize Now'}" "$HOTFIX"; then
  fail "fragile UI action discovery returned"
fi
if grep -Fq 'ast.get_source_segment' "$HOTFIX"; then
  fail "fragile UI action source replacement returned"
fi
grep -Fq 'mechos-auto-optimization-hotfix.sh' "$PATCHER" || fail "backend hotfix is not wired into the final build chain"

echo '[validate-auto-optimization] OK: Performance Center set_profile backend is VM/hardware-aware and no longer depends on UI button rewriting'
