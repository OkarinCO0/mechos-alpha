#!/usr/bin/env bash
set -Eeuo pipefail

BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INTEGRATION="$BASE/scripts/mechos-reference-ui-integration.sh"
PATCHER="$BASE/scripts/patch-mechos-current.py"
DESIGN="$BASE/docs/UI-DESIGN-STANDARD.md"

fail() { echo "Reference UI validation error: $*" >&2; exit 1; }

[ -f "$INTEGRATION" ] || fail "reference UI integration is missing"
[ -f "$PATCHER" ] || fail "cumulative patcher is missing"
[ -f "$DESIGN" ] || fail "UI design standard is missing"

bash -n "$INTEGRATION" || fail "reference UI integration shell syntax failed"

grep -Fq 'MECHOS_REFERENCE_UI_V2' "$INTEGRATION" || fail "reference UI marker is missing"
grep -Fq 'CONTROLLER_FOCUS=#a87cff' "$INTEGRATION" || fail "controller focus token is missing"
grep -Fq 'QFrame#hero' "$INTEGRATION" || fail "hero surface styling is missing"
grep -Fq 'QFrame#panel' "$INTEGRATION" || fail "card/panel styling is missing"
grep -Fq 'QPushButton:focus' "$INTEGRATION" || fail "controller/keyboard focus styling is missing"
grep -Fq 'QProgressBar::chunk' "$INTEGRATION" || fail "reference progress styling is missing"
grep -Fq 'mechos-reference-ui-integration.sh final' "$PATCHER" || fail "reference UI is not wired into cumulative build"

grep -Fq 'Master reference' "$DESIGN" || fail "design standard does not define the master reference"
grep -Fq 'MechScope' "$DESIGN" || fail "design standard does not cover MechScope"
grep -Fq 'Installer' "$DESIGN" || fail "design standard does not cover Installer"
grep -Fq 'Creator Mode' "$DESIGN" || fail "design standard does not cover Creator Mode"

echo "MechOS graphical reference UI validation passed."
