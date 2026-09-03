#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UI="$ROOT/src/mechos_ui"
INTEGRATION="$ROOT/scripts/mechos-source-owned-system-ui.sh"
PATCHER="$ROOT/scripts/patch-mechos-reference-v5.py"
CREATOR_REF="$ROOT/branding/mechos-creator-mode-reference.png"
fail(){ echo "[validate-source-system-ui] ERROR: $*" >&2; exit 1; }

[ -d "$UI" ] || fail "src/mechos_ui missing"
[ -f "$INTEGRATION" ] || fail "system UI integration missing"
[ -f "$PATCHER" ] || fail "reference v5 patcher missing"
[ -s "$CREATOR_REF" ] || fail "approved Creator Mode reference artwork missing"
bash -n "$INTEGRATION" || fail "integration shell syntax failed"

# `bash -n` does not catch nounset expansion ordering. Reject declarations that
# build a dependent local in the same statement that first assigns it.
if grep -Eq 'local[[:space:]]+tree="\$1".*name="\$2".*public=.*\$name' "$INTEGRATION"; then
  fail "unsafe dependent local assignment can fail under set -u"
fi
grep -Fq 'local tree="$1"' "$INTEGRATION" || fail "owner_file tree assignment missing"
grep -Fq 'local name="$2"' "$INTEGRATION" || fail "owner_file name assignment missing"
grep -Fq 'local public="$tree/usr/local/bin/$name"' "$INTEGRATION" || fail "owner_file public assignment missing"

python3 -m py_compile \
  "$UI/fixed_canvas.py" \
  "$UI/creator_shell.py" \
  "$UI/performance_shell.py" \
  "$UI/update_shell.py" \
  "$UI/recovery_shell.py" \
  "$UI/quick_actions_shell.py" || fail "source UI Python syntax failed"

for f in creator_shell.py performance_shell.py update_shell.py recovery_shell.py quick_actions_shell.py; do
  [ -f "$UI/$f" ] || fail "$f missing"
  if grep -Eq '\b(QHBoxLayout|QVBoxLayout|QGridLayout)\b' "$UI/$f"; then
    fail "$f regressed to layout-driven visual composition"
  fi
done

grep -Fq 'BASE_W=1920' "$UI/fixed_canvas.py" || fail "shared 1920 design canvas missing"
grep -Fq 'class CreatorShell' "$UI/creator_shell.py" || fail "Creator Mode source shell missing"
grep -Fq 'class ReferenceHome' "$UI/creator_shell.py" || fail "Creator reference home renderer missing"
grep -Fq '/usr/share/mechos/branding/mechos-creator-mode-reference.png' "$UI/creator_shell.py" || fail "Creator runtime does not use approved reference artwork"
grep -Fq "painter.drawPixmap(target, self.reference)" "$UI/creator_shell.py" || fail "Creator reference artwork is not painted as the Home visual layer"
grep -Fq "self.owner.nav = []" "$UI/creator_shell.py" || fail "legacy Creator sidebar was not removed"
if grep -Fq 'CreatorDashboard' "$UI/creator_shell.py"; then
  fail "legacy recreated Creator dashboard still present"
fi
grep -Fq 'CREATOR APPS & ENGINES' "$UI/creator_shell.py" || fail "Creator reference section markers missing"
grep -Fq "Back to MechScope" "$UI/creator_shell.py" || fail "reference bottom navigation hotspot missing"

grep -Fq 'class QuickActionsShell' "$UI/quick_actions_shell.py" || fail "Quick Actions source shell missing"
grep -Fq 'STREAMING & RECORDING' "$UI/quick_actions_shell.py" || fail "Quick Actions mockup sections missing"
grep -Fq 'class PerformanceShell' "$UI/performance_shell.py" || fail "Performance source shell missing"
grep -Fq 'LIVE SYSTEM METRICS' "$UI/performance_shell.py" || fail "Performance mockup metrics missing"
grep -Fq 'class UpdateShell' "$UI/update_shell.py" || fail "Update source shell missing"
grep -Fq 'UPDATE CATEGORIES' "$UI/update_shell.py" || fail "Update mockup categories missing"
grep -Fq 'class RecoveryShell' "$UI/recovery_shell.py" || fail "Recovery source shell missing"
grep -Fq 'RECOVERY ACTIONS' "$UI/recovery_shell.py" || fail "Recovery mockup actions missing"

grep -Fq 'MECHOS_SOURCE_SYSTEM_UI_V1_CREATOR' "$INTEGRATION" || fail "Creator runtime override missing"
grep -Fq 'MECHOS_SOURCE_SYSTEM_UI_V1_QUICK' "$INTEGRATION" || fail "Quick Actions runtime override missing"
grep -Fq 'MECHOS_SOURCE_SYSTEM_UI_V1_PERFORMANCE' "$INTEGRATION" || fail "Performance runtime override missing"
grep -Fq 'MECHOS_SOURCE_SYSTEM_UI_V1_UPDATE' "$INTEGRATION" || fail "Update runtime override missing"
grep -Fq 'MECHOS_SOURCE_SYSTEM_UI_V1_RECOVERY' "$INTEGRATION" || fail "Recovery runtime override missing"
grep -Fq 'mechos-source-owned-system-ui.sh' "$PATCHER" || fail "source-owned UI is not in final build chain"

# The builder must put the exact approved reference into the runtime root.
grep -Fq '/workspace/branding/mechos-creator-mode-reference.png' "$ROOT/scripts/build-mechos-archiso.sh" || fail "builder does not source approved Creator reference"
grep -Fq '/usr/share/mechos/branding/mechos-creator-mode-reference.png' "$ROOT/scripts/build-mechos-archiso.sh" || fail "builder does not install Creator reference into runtime"

python3 - "$PATCHER" <<'PY'
from pathlib import Path
import sys
text=Path(sys.argv[1]).read_text()
a=text.find('mechos-auto-optimization-hotfix.sh')
b=text.find('mechos-source-owned-system-ui.sh')
c=text.find('mechos-reference-v5-postinstall-stage.sh commit')
if min(a,b,c)<0 or not (a < b < c):
    raise SystemExit('[validate-source-system-ui] source UI must run after runtime hotfixes and before postinstall commit')
PY

echo '[validate-source-system-ui] OK: Creator Mode Home renders the approved reference artwork directly and keeps functional hotspots; other source-owned system screens remain validated'
