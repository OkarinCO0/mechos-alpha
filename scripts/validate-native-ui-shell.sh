#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_SRC="$ROOT/src/mechscope/mechscope_shell.py"
INTEGRATION="$ROOT/scripts/mechos-native-ui-shell-integration.sh"
PATCHER="$ROOT/scripts/patch-mechos-reference-v5.py"

fail(){ echo "[validate-native-ui-shell] ERROR: $*" >&2; exit 1; }

[ -f "$SHELL_SRC" ] || fail "source-owned MechScope shell missing"
[ -f "$INTEGRATION" ] || fail "native UI integration missing"
[ -f "$PATCHER" ] || fail "reference-v5 patcher missing"

python3 -m py_compile "$SHELL_SRC" || fail "MechScope shell Python syntax failed"
bash -n "$INTEGRATION" || fail "native UI integration shell syntax failed"

grep -Fq 'BASE_W = 1672' "$SHELL_SRC" || fail "approved 1672px MechScope reference canvas missing"
grep -Fq 'BASE_H = 941' "$SHELL_SRC" || fail "approved 941px MechScope reference canvas missing"
grep -Fq 'SYSTEM STATUS' "$SHELL_SRC" || fail "reference System Status surface missing"
grep -Fq 'RECENT GAMES' "$SHELL_SRC" || fail "reference Recent Games surface missing"
grep -Fq 'QUICK ACTIONS' "$SHELL_SRC" || fail "reference Quick Actions surface missing"
grep -Fq 'QUICK MODES' "$SHELL_SRC" || fail "reference Quick Modes surface missing"
grep -Fq 'MechScope 2.0' "$SHELL_SRC" || fail "reference hero title missing"
grep -Fq 'QRadialGradient' "$SHELL_SRC" || fail "reference hero planet/glow treatment missing"
grep -Fq 'setGeometry' "$SHELL_SRC" || fail "explicit reference geometry scaling missing"
grep -Fq 'font_sizes' "$SHELL_SRC" || fail "MechScope typography scaling missing"
if grep -Eq '(^|[^A-Za-z0-9_])Q(HBox|VBox|Grid)Layout[[:space:]]*\(' "$SHELL_SRC"; then
  fail "source-owned MechScope shell regressed to nested Qt layout construction"
fi
if grep -Eq '^from PyQt6\.QtWidgets import .*Q(HBox|VBox|Grid)Layout' "$SHELL_SRC"; then
  fail "source-owned MechScope shell imports nested Qt layouts"
fi

grep -Fq 'MECHOS_SOURCE_OWNED_SHELL_V3' "$INTEGRATION" || fail "safe runtime source-shell marker missing"
grep -Fq 'MechScopeShell' "$INTEGRATION" || fail "runtime does not install MechScopeShell"
grep -Fq 'MechScope.build_ui=_mechos_native_build_ui' "$INTEGRATION" || fail "safe build_ui runtime override missing"
grep -Fq 'MechScope.refresh_stats=_mechos_native_refresh_stats' "$INTEGRATION" || fail "safe refresh_stats runtime override missing"
grep -Fq 'self.showFullScreen()' "$INTEGRATION" || fail "MechScope true fullscreen enforcement missing"
grep -Fq '_MechQTimer.singleShot(0' "$INTEGRATION" || fail "post-show fullscreen assertion missing"
grep -Fq '_MechQTimer.singleShot(750' "$INTEGRATION" || fail "late fullscreen assertion missing"
grep -Fq 'Qt.WindowType.FramelessWindowHint' "$INTEGRATION" || fail "frameless MechScope flag missing"
if grep -Fq "text=replace_method(text,'build_ui'" "$INTEGRATION"; then
  fail "unsafe generated-class method surgery returned"
fi
if grep -Fq "text=replace_method(text,'refresh_stats'" "$INTEGRATION"; then
  fail "unsafe generated-class method surgery returned"
fi

grep -Fq 'mechos-native-ui-shell-integration.sh' "$PATCHER" || fail "source-owned shell is not wired as final Reference v5 authority"

echo '[validate-native-ui-shell] OK: MechScope uses approved 1672x941 reference composition, safe runtime overrides and true fullscreen startup'
