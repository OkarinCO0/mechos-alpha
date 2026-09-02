#!/usr/bin/env bash
set -Eeuo pipefail

BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INTEGRATION="$BASE/scripts/mechos-reference-surfaces-v4-integration.sh"
PATCHER="$BASE/scripts/patch-mechos-current.py"

fail() { echo "Reference Surfaces v4 validation error: $*" >&2; exit 1; }

[ -f "$INTEGRATION" ] || fail "Reference Surfaces v4 integration is missing"
[ -f "$PATCHER" ] || fail "cumulative patcher is missing"
bash -n "$INTEGRATION" || fail "Reference Surfaces v4 shell syntax failed"

grep -Fq 'MECHOS_REFERENCE_SURFACES_V4' "$INTEGRATION" || fail "Performance Center v4 marker is missing"
grep -Fq 'MECHOS_REFERENCE_UPDATE_V4' "$INTEGRATION" || fail "Update Center v4 layout is missing"
grep -Fq 'MECHOS_REFERENCE_QUICK_ACTIONS_V4' "$INTEGRATION" || fail "Quick Actions v4 layout is missing"
grep -Fq 'MECHOS_REFERENCE_STREAM_V4' "$INTEGRATION" || fail "Stream Center v4 layout is missing"
grep -Fq 'MECHOS_REFERENCE_RECOVERY_V4' "$INTEGRATION" || fail "Recovery Center v4 layout is missing"
grep -Fq 'MECHOS_REFERENCE_CREATOR_MODE_V4' "$INTEGRATION" || fail "Creator Mode v4 fullscreen marker is missing"
grep -Fq 'MECHOS_CREATOR_READY_HANDOFF_V4' "$INTEGRATION" || fail "Creator readiness handoff is missing"
grep -Fq 'MECHOS_RADARAI_PERFORMANCE_CENTER_V1' "$INTEGRATION" || fail "RadarAI compatibility marker is missing"
grep -Fq 'mechos-reference-surfaces-v4-integration.sh final' "$PATCHER" || fail "Reference Surfaces v4 is not wired into the ISO builder"

echo "Reference Surfaces v4 source validation passed."
