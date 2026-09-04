#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/scripts/mechos-new-build-final-gate.sh"
PATCHER="$ROOT/scripts/patch-mechos-reference-v5.py"
fail(){ echo "[validate-new-build-final-gate] ERROR: $*" >&2; exit 1; }

[ -f "$GATE" ] || fail "final clean-build gate is missing"
bash -n "$GATE" || fail "final clean-build gate has invalid shell syntax"
[ -f "$PATCHER" ] || fail "Reference v5 patcher is missing"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$PATCHER" || fail "Reference v5 patcher has invalid Python syntax"

grep -Fq 'MECHOS_FINAL_USER_UPDATE_CACHE_V1' "$GATE" || fail "user-writable update cache repair missing"
grep -Fq 'XDG_CACHE_HOME' "$GATE" || fail "per-user update cache path missing"
grep -Fq 'Exec=/usr/local/bin/mechos-mode-launch gaming' "$GATE" || fail "Return to MechScope does not use shared launcher"
grep -Fq 'Exec=/usr/local/bin/mechos-mode-launch creator' "$GATE" || fail "Creator Mode does not use shared launcher"
grep -Fq 'systemd-detect-virt' "$GATE" || fail "VM/physical runtime detection missing"
grep -Fq 'nohup /usr/local/bin/mechscope' "$GATE" || fail "MechScope direct fallback missing"
grep -Fq 'nohup /usr/local/bin/mechos-creator-mode' "$GATE" || fail "Creator direct fallback missing"
grep -Fq 'mechos-firstboot-authority.service' "$GATE" || fail "first-boot OOBE authority missing"
grep -Fq 'User=mechos-setup' "$GATE" || fail "temporary setup account handoff missing"
grep -Fq 'Exec=/usr/local/bin/mechos-oobe-start' "$GATE" || fail "OOBE automatic launcher missing"
grep -Fq 'MECHOS_CREATOR_REFERENCE_NATIVE_SCALE_V2' "$GATE" || fail "Creator alignment final repair missing"
grep -Fq 'MECHOS_NEW_BUILD_FINAL_GATE_V1' "$GATE" || fail "post-install final gate marker missing"
grep -Fq "printf '0.3.0-hotfix.2\\n'" "$GATE" || fail "installed release metadata is not aligned with Hotfix 2"

finalizer_line="$(grep -n 'mechos-finalize-install-payload.sh final' "$PATCHER" | tail -n1 | cut -d: -f1)"
gate_line="$(grep -n 'mechos-new-build-final-gate.sh' "$PATCHER" | tail -n1 | cut -d: -f1)"
[ -n "$finalizer_line" ] || fail "payload finalizer call missing"
[ -n "$gate_line" ] || fail "new-build final gate is not wired into the build"
[ "$gate_line" -gt "$finalizer_line" ] || fail "new-build gate must run after payload finalization"

echo '[validate-new-build-final-gate] OK: OOBE, updater, VM/hardware mode switching, Creator alignment and final build order are guarded'
