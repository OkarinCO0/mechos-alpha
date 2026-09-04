#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UI="$ROOT/src/mechos_ui"
INTEGRATION="$ROOT/scripts/mechos-source-owned-system-ui.sh"
PATCHER="$ROOT/scripts/patch-mechos-reference-v5.py"
INSTALLER_FALLBACK="$ROOT/scripts/mechos-live-installer-crash-fallback.sh"
INSTALLER_REF="$ROOT/branding/mechos-installer-reference.png"
fail(){ echo "[validate-source-system-ui] ERROR: $*" >&2; exit 1; }

[ -d "$UI" ] || fail "src/mechos_ui missing"
[ -f "$INTEGRATION" ] || fail "system UI integration missing"
[ -f "$PATCHER" ] || fail "reference v5 patcher missing"
[ -f "$INSTALLER_FALLBACK" ] || fail "Live installer crash fallback missing"
[ -s "$INSTALLER_REF" ] || fail "approved Installer reference artwork missing"
bash -n "$INTEGRATION" || fail "integration shell syntax failed"

if grep -Eq 'local[[:space:]]+tree="\$1".*name="\$2".*public=.*\$name' "$INTEGRATION"; then
  fail "unsafe dependent local assignment can fail under set -u"
fi
grep -Fq 'local tree="$1"' "$INTEGRATION" || fail "owner_file tree assignment missing"
grep -Fq 'local name="$2"' "$INTEGRATION" || fail "owner_file name assignment missing"
grep -Fq 'local public="$tree/usr/local/bin/$name"' "$INTEGRATION" || fail "owner_file public assignment missing"
grep -Fq 'local libexec_v5="$tree/usr/local/libexec/${name}-v5.py"' "$INTEGRATION" || fail "owner_file v5 libexec fallback missing"
grep -Fq 'grep -Fq "class $cls(" "$libexec_v5"' "$INTEGRATION" || fail "owner_file does not inspect v5 libexec implementation"
grep -Fq 'REAL="$ROOT/usr/local/libexec/mechos-live-setup-v5.py"' "$INSTALLER_FALLBACK" || fail "Live installer fallback real-owner path changed unexpectedly"

python3 -m py_compile \
  "$UI/fixed_canvas.py" \
  "$UI/creator_shell.py" \
  "$UI/performance_shell.py" \
  "$UI/update_shell.py" \
  "$UI/recovery_shell.py" \
  "$UI/quick_actions_shell.py" \
  "$UI/installer_shell.py" \
  "$UI/oobe_shell.py" || fail "source UI Python syntax failed"

for f in creator_shell.py performance_shell.py update_shell.py recovery_shell.py quick_actions_shell.py installer_shell.py oobe_shell.py; do
  [ -f "$UI/$f" ] || fail "$f missing"
  if grep -Eq '\b(QHBoxLayout|QVBoxLayout|QGridLayout|QFormLayout)\b' "$UI/$f"; then
    fail "$f regressed to layout-driven visual composition"
  fi
done

# Shared geometry/scaling authority.
grep -Fq 'BASE_W = 1920' "$UI/fixed_canvas.py" || fail "shared 1920 design canvas missing"
grep -Fq 'BASE_H = 1080' "$UI/fixed_canvas.py" || fail "shared 1080 design canvas missing"
grep -Fq 'def scale_factor' "$UI/fixed_canvas.py" || fail "shared aspect-preserving scale factor missing"
grep -Fq '_font_sizes' "$UI/fixed_canvas.py" || fail "shared typography scaling missing"
grep -Fq 'base * s' "$UI/fixed_canvas.py" || fail "shared scaled-font application missing"

# Creator Mode must be a real live dashboard, never a screenshot with hit zones.
CREATOR="$UI/creator_shell.py"
grep -Fq 'class CreatorShell' "$CREATOR" || fail "Creator Mode source shell missing"
grep -Fq 'class LiveCreatorHome' "$CREATOR" || fail "live Creator home missing"
grep -Fq 'scan_local_projects' "$CREATOR" || fail "Creator real project scan missing"
grep -Fq 'No creator projects found on this PC' "$CREATOR" || fail "Creator empty-project state missing"
grep -Fq '/proc/meminfo' "$CREATOR" || fail "Creator live RAM telemetry missing"
grep -Fq '/proc/stat' "$CREATOR" || fail "Creator live CPU telemetry missing"
grep -Fq 'lspci -nnk' "$CREATOR" || fail "Creator real GPU/driver detection missing"
grep -Fq 'UPDATE_HELPER = Path("/usr/local/bin/mechos-update-helper")' "$CREATOR" || fail "Creator live update source missing"
grep -Fq 'CURRENT_MECHOS_VERSION' "$CREATOR" || fail "Creator update manifest parsing missing"
grep -Fq 'MECHOS_UPDATE_AVAILABLE' "$CREATOR" || fail "Creator update availability parsing missing"
grep -Fq '_app_installed' "$CREATOR" || fail "Creator real app-state detection missing"
grep -Fq 'Open Performance Center' "$CREATOR" || fail "Creator Performance Center action missing"
grep -Fq 'MechScope' "$CREATOR" || fail "Creator MechScope navigation missing"
grep -Fq 'self.owner.nav = []' "$CREATOR" || fail "legacy Creator sidebar ownership was not removed"
if grep -Fq 'REFERENCE_IMAGE =' "$CREATOR"; then fail "Creator returned to full-screen reference raster"; fi
if grep -Fq 'painter.drawPixmap(target, self.reference)' "$CREATOR"; then fail "Creator still paints the screenshot as its dashboard"; fi
if grep -Fq 'class ReferenceHome' "$CREATOR"; then fail "legacy screenshot-backed Creator home survived"; fi

# Installer may use the approved reference chrome, but all demo data must be replaced.
grep -Fq 'class InstallerShell' "$UI/installer_shell.py" || fail "reference-backed Installer shell missing"
grep -Fq '/usr/share/mechos/branding/mechos-installer-reference.png' "$UI/installer_shell.py" || fail "Installer does not use approved reference artwork"
grep -Fq 'painter.drawPixmap(target, self.reference)' "$UI/installer_shell.py" || fail "Installer reference artwork is not painted as visual layer"
grep -Fq 'Mask only the demo-data regions' "$UI/installer_shell.py" || fail "Installer reference demo-data masking missing"
grep -Fq 'SELECT INSTALL TARGET' "$UI/installer_shell.py" || fail "Installer real target region missing"
grep -Fq 'INSTALLATION OPTIONS' "$UI/installer_shell.py" || fail "Installer real install-mode region missing"
grep -Fq 'SYSTEM SUMMARY' "$UI/installer_shell.py" || fail "Installer real hardware region missing"
grep -Fq "RELEASE = Path('/etc/mechos/release')" "$UI/installer_shell.py" || fail "Installer runtime version source missing"
grep -Fq 'Install Now' "$UI/installer_shell.py" || fail "Installer functional install hotspot missing"

# OOBE.
grep -Fq 'class OOBEShell' "$UI/oobe_shell.py" || fail "source-owned OOBE shell missing"
grep -Fq 'FIRST SYSTEM SETUP' "$UI/oobe_shell.py" || fail "OOBE MechOS header missing"
grep -Fq 'Create your MechOS account.' "$UI/oobe_shell.py" || fail "OOBE account surface missing"
grep -Fq 'Ready to finish setup.' "$UI/oobe_shell.py" || fail "OOBE review surface missing"

# Quick Actions scaling.
grep -Fq 'class QuickActionsShell' "$UI/quick_actions_shell.py" || fail "Quick Actions source shell missing"
grep -Fq 'def scale_factor' "$UI/quick_actions_shell.py" || fail "Quick Actions uniform scaling missing"
grep -Fq 'min(self.width()/self.BASE_W, self.height()/self.BASE_H)' "$UI/quick_actions_shell.py" || fail "Quick Actions aspect preservation missing"
if grep -Eq 'sx=self\.width\(\).*sy=self\.height\(\)' "$UI/quick_actions_shell.py"; then fail "Quick Actions independent X/Y stretching returned"; fi
grep -Fq 'STREAMING & RECORDING' "$UI/quick_actions_shell.py" || fail "Quick Actions sections missing"

# Remaining system surfaces.
grep -Fq 'class PerformanceShell' "$UI/performance_shell.py" || fail "Performance source shell missing"
grep -Fq 'LIVE SYSTEM METRICS' "$UI/performance_shell.py" || fail "Performance metrics missing"
grep -Fq "QRect(x,202,190,92),34" "$UI/performance_shell.py" || fail "Performance metric typography is not tracked by shared scale"
grep -Fq 'class UpdateShell' "$UI/update_shell.py" || fail "Update source shell missing"
grep -Fq 'UPDATE CATEGORIES' "$UI/update_shell.py" || fail "Update categories missing"
grep -Fq 'class RecoveryShell' "$UI/recovery_shell.py" || fail "Recovery source shell missing"
grep -Fq 'RECOVERY ACTIONS' "$UI/recovery_shell.py" || fail "Recovery actions missing"

# Final runtime overrides.
for marker in CREATOR QUICK PERFORMANCE UPDATE RECOVERY OOBE INSTALLER; do
  grep -Fq "MECHOS_SOURCE_SYSTEM_UI_V1_${marker}" "$INTEGRATION" || fail "$marker runtime override missing"
done
grep -Fq 'installer_shell.py' "$INTEGRATION" || fail "Installer source is not installed"
grep -Fq 'creator_shell.py' "$INTEGRATION" || fail "Creator source is not installed"
grep -Fq 'oobe_shell.py' "$INTEGRATION" || fail "OOBE source is not installed"
grep -Fq 'mechos-live-setup Installer' "$INTEGRATION" || fail "Live Installer owner is not patched by final source UI authority"
grep -Fq 'mechos-oobe OOBE' "$INTEGRATION" || fail "OOBE owner is not patched by final source UI authority"
grep -Fq 'mechos-source-owned-system-ui.sh' "$PATCHER" || fail "source-owned UI is not in final build chain"

# Only Installer requires a runtime raster reference now.
grep -Fq '/workspace/branding/mechos-installer-reference.png' "$ROOT/scripts/build-mechos-archiso.sh" || fail "builder does not source approved Installer reference"
grep -Fq '/usr/share/mechos/branding/mechos-installer-reference.png' "$ROOT/scripts/build-mechos-archiso.sh" || fail "builder does not install Installer reference"

python3 - "$PATCHER" <<'PY'
from pathlib import Path
import sys
text=Path(sys.argv[1]).read_text()
a=text.find('mechos-auto-optimization-hotfix.sh')
b=text.find('mechos-source-owned-system-ui.sh')
c=text.find('mechos-reference-splash-integration.sh')
d=text.find('mechos-reference-v5-postinstall-stage.sh commit')
if min(a,b,c,d)<0 or not (a < b < c < d):
    raise SystemExit('[validate-source-system-ui] final source UI must run after runtime hotfixes and before splash/postinstall commit')
PY

echo '[validate-source-system-ui] OK: Creator is a native live dashboard with real host telemetry/projects/update state; Installer keeps approved chrome with real runtime data; all system surfaces remain source-owned and aspect-preserving'
