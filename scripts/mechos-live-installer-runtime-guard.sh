#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
BIN="$ROOT/usr/local/bin"
LIBEXEC="$ROOT/usr/local/libexec"
PROFILE="/workspace/archlive/profiledef.sh"
TARGET="$BIN/mechos-live-setup"
REAL="$LIBEXEC/mechos-live-setup-v5.py"

log() { printf '[MechOS Live Installer Guard] %s\n' "$*"; }
fail() { printf '[MechOS Live Installer Guard] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Live Installer Guard] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ -f "$TARGET" ] || fail "Live graphical installer is missing: $TARGET"
mkdir -p "$LIBEXEC"

# Reference UI v5 replaces the Installer class late in the build. Python bytecode
# compilation catches syntax errors, but it does not catch a missing Qt symbol
# that is only resolved when Installer.__init__ actually runs. Make the final
# runtime self-contained instead of inheriting whichever imports an older
# installer revision happened to provide.
python3 - "$TARGET" <<'PY'
from pathlib import Path
import sys

path=Path(sys.argv[1])
text=path.read_text(encoding='utf-8')
marker='# MECHOS_LIVE_INSTALLER_RUNTIME_IMPORTS_V1'
if marker not in text:
    anchor='class Installer(QMainWindow):'
    pos=text.find(anchor)
    if pos < 0:
        raise SystemExit('[MechOS Live Installer Guard] Installer class not found')
    imports='''# MECHOS_LIVE_INSTALLER_RUNTIME_IMPORTS_V1
from PyQt6.QtCore import Qt, QTimer
from PyQt6.QtGui import QPixmap
from PyQt6.QtWidgets import (
    QApplication, QButtonGroup, QFrame, QHBoxLayout, QLabel, QListWidget,
    QListWidgetItem, QMainWindow, QMessageBox, QProgressBar, QPushButton,
    QRadioButton, QVBoxLayout, QWidget
)

'''
    text=text[:pos]+imports+text[pos:]

required=(
    'import json', 'import os', 'import subprocess', 'from pathlib import Path',
    'from PyQt6.QtCore import Qt, QTimer', 'from PyQt6.QtGui import QPixmap',
    'QButtonGroup', 'QListWidgetItem', 'QRadioButton',
    'MECHOS_REFERENCE_INSTALLER_V5',
)
for item in required:
    if item not in text:
        raise SystemExit(f'[MechOS Live Installer Guard] final installer missing runtime requirement: {item}')
compile(text,str(path),'exec')
path.write_text(text,encoding='utf-8')
PY

PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$TARGET" \
  || fail "final Live installer Python syntax failed"

grep -Fq 'MECHOS_LIVE_INSTALLER_RUNTIME_IMPORTS_V1' "$TARGET" \
  || fail "explicit v5 runtime imports were not installed"
grep -Fq 'MECHOS_REFERENCE_INSTALLER_V5' "$TARGET" \
  || fail "Reference Installer v5 disappeared before runtime guard"

# Preserve the real Python application and put a tiny Bash launch guard at the
# public path. This lets VM graphics use a conservative software path while
# physical AMD/Intel/NVIDIA systems keep their normal Qt rendering path.
mv -f "$TARGET" "$REAL"
chmod 755 "$REAL"

cat > "$TARGET" <<'WRAPPER'
#!/usr/bin/env bash
set -Eeuo pipefail

REAL=/usr/local/libexec/mechos-live-setup-v5.py
LOG=/tmp/mechos-live-setup.log

{
  printf '\n=== MechOS Live Installer %s ===\n' "$(date -Is 2>/dev/null || date)"
  printf 'Session=%s Wayland=%s Display=%s\n' "${XDG_SESSION_TYPE:-unknown}" "${WAYLAND_DISPLAY:-}" "${DISPLAY:-}"

  virt="$(systemd-detect-virt 2>/dev/null || true)"
  case "$virt" in
    ""|none) ;;
    *)
      # VirtualBox/VMware/QEMU virtual GPUs have repeatedly faulted in the Qt/GL
      # path during Live testing. The installer is QWidget-based, so software
      # rendering is sufficient and avoids losing the installer before it opens.
      export QT_OPENGL=software
      export LIBGL_ALWAYS_SOFTWARE=1
      export QT_QUICK_BACKEND=software
      export QSG_RHI_BACKEND=software
      printf 'Virtualization=%s; using VM-safe software Qt rendering.\n' "$virt"
      ;;
  esac

  export PYTHONFAULTHANDLER=1
  exec /usr/bin/python3 -X faulthandler "$REAL" "$@"
} >>"$LOG" 2>&1
WRAPPER
chmod 755 "$TARGET"

bash -n "$TARGET" || fail "Live installer wrapper shell syntax failed"
[ -x "$REAL" ] || fail "Live installer Python implementation was not preserved"

if [ -f "$PROFILE" ]; then
  for path in /usr/local/bin/mechos-live-setup /usr/local/libexec/mechos-live-setup-v5.py; do
    if ! grep -Fq "file_permissions[\"$path\"]" "$PROFILE"; then
      printf '\nfile_permissions["%s"]="0:0:755"\n' "$path" >> "$PROFILE"
    fi
  done
fi

log "Live installer has explicit Qt imports, VM-safe rendering and crash logging"
