#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
PAYLOAD="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"

log() { printf '[MechScope Shell] %s\n' "$*"; }
fail() { printf '[MechScope Shell] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechScope Shell] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"
[ -f "$ROOT/usr/local/bin/mechscope" ] || fail "MechScope runtime is missing"
[ -f "$ROOT/usr/local/bin/mechos-gaming-session" ] || fail "MechOS gaming session is missing"

patch_tree() {
  local tree="$1"
  local mechscope="$tree/usr/local/bin/mechscope"
  local session="$tree/usr/local/bin/mechos-gaming-session"

  [ -f "$mechscope" ] || fail "MechScope missing in tree: $tree"
  [ -f "$session" ] || fail "gaming session missing in tree: $tree"

  python3 - "$mechscope" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
marker = '# MECHOS_FULLSCREEN_SHELL_V1'

if marker not in text:
    old = '''        self.setWindowTitle("MechScope Unified Store")
        self.resize(1050,720)
'''
    new = '''        self.setWindowTitle("MechScope Unified Store")
        # MECHOS_FULLSCREEN_SHELL_V1
        # The Store is a MechScope surface, not a KDE desktop window.
        self.setWindowFlag(Qt.WindowType.FramelessWindowHint, True)
        self.setWindowState(Qt.WindowState.WindowFullScreen)
        self.setModal(True)
        self.resize(1050,720)
'''
    if old not in text:
        raise SystemExit('[MechScope Shell] could not locate Unified Store window setup')
    text = text.replace(old, new, 1)

    old = '''    def open_store(self):
        dialog=UnifiedStore(self)
        dialog.exec()
'''
    new = '''    def open_store(self):
        # Keep Store navigation inside the full-screen MechScope experience.
        dialog=UnifiedStore(self)
        dialog.showFullScreen()
        dialog.exec()
'''
    if old not in text:
        raise SystemExit('[MechScope Shell] could not locate MechScope Store launch method')
    text = text.replace(old, new, 1)

    old = '''if "--store" in sys.argv:
    dialog=UnifiedStore(); dialog.showMaximized(); sys.exit(app.exec())
'''
    new = '''if "--store" in sys.argv:
    # Standalone Store testing still uses the console-style full-screen surface.
    dialog=UnifiedStore(); dialog.showFullScreen(); sys.exit(app.exec())
'''
    if old not in text:
        raise SystemExit('[MechScope Shell] could not locate standalone Store launch path')
    text = text.replace(old, new, 1)

path.write_text(text, encoding='utf-8')
PY

  python3 - "$session" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
marker = '# MECHOS_PLASMA_FALLBACK_SHELL_V1'

if marker not in text:
    old = '''  (
    sleep 4
    echo "===== MechScope fallback $(date -Is) =====" >>"$MECHSCOPE_LOG"
    /usr/local/bin/mechscope >>"$MECHSCOPE_LOG" 2>&1
  ) &
'''
    new = '''  (
    sleep 4
    # MECHOS_PLASMA_FALLBACK_SHELL_V1
    # Plasma supplies the compositor only. Hide its desktop shell/panel while
    # MechScope owns Gaming Mode so VM fallback looks like the real console UI.
    if command -v kquitapp6 >/dev/null 2>&1; then
      kquitapp6 plasmashell >/dev/null 2>&1 || true
    elif command -v kquitapp5 >/dev/null 2>&1; then
      kquitapp5 plasmashell >/dev/null 2>&1 || true
    else
      pkill -x plasmashell >/dev/null 2>&1 || true
    fi

    echo "===== MechScope fallback $(date -Is) =====" >>"$MECHSCOPE_LOG"
    /usr/local/bin/mechscope >>"$MECHSCOPE_LOG" 2>&1

    # MechScope exited (for Desktop Mode, Creator Mode, or a crash). Restore the
    # Plasma shell so the safe fallback never leaves the user without a panel.
    if command -v plasmashell >/dev/null 2>&1 && ! pgrep -x plasmashell >/dev/null 2>&1; then
      nohup plasmashell --replace >>"$MECHSCOPE_LOG" 2>&1 &
    fi
  ) &
'''
    if old not in text:
        raise SystemExit('[MechScope Shell] could not locate Plasma fallback launch block')
    text = text.replace(old, new, 1)

path.write_text(text, encoding='utf-8')
PY

  chmod 755 "$mechscope" "$session"
  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$mechscope" \
    || fail "MechScope Python validation failed"
  bash -n "$session" || fail "gaming-session shell validation failed"

  grep -Fq 'MECHOS_FULLSCREEN_SHELL_V1' "$mechscope" \
    || fail "full-screen Store marker is missing"
  grep -Fq 'dialog.showFullScreen()' "$mechscope" \
    || fail "Store is not forced full-screen"
  grep -Fq 'MECHOS_PLASMA_FALLBACK_SHELL_V1' "$session" \
    || fail "Plasma fallback shell-hiding marker is missing"
  grep -Fq 'gamescope -e -f --mangoapp -- /usr/local/bin/mechscope' "$session" \
    || fail "gaming session no longer launches the custom MechScope shell"
}

patch_tree "$ROOT"

# The installed system is deployed from this archive. Patch it too so the Live
# image and the post-install MechScope runtime cannot drift apart.
if [ -s "$PAYLOAD" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  tar --zstd -xf "$PAYLOAD" -C "$tmp"
  patch_tree "$tmp"
  replacement="$PAYLOAD.mechscope"
  tar --zstd -cf "$replacement" -C "$tmp" .
  mv -f "$replacement" "$PAYLOAD"
  rm -rf "$tmp"
  trap - EXIT
else
  fail "installed-system payload is missing: $PAYLOAD"
fi

log "MechScope now owns Gaming Mode; Unified Store is frameless/full-screen and Plasma fallback hides desktop chrome while MechScope is active"
