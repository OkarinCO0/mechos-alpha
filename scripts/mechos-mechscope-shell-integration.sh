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

resolve_mechscope_target() {
  local tree="$1"
  # The tutorial integration wraps MechScope and moves the actual PyQt program
  # to mechscope.real. Always patch the real GUI when that wrapper is present.
  if [ -f "$tree/usr/local/bin/mechscope.real" ]; then
    printf '%s\n' "$tree/usr/local/bin/mechscope.real"
  else
    printf '%s\n' "$tree/usr/local/bin/mechscope"
  fi
}

patch_mechscope_gui() {
  local mechscope="$1"

  python3 - "$mechscope" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
marker = '# MECHOS_FULLSCREEN_SHELL_V1'

if 'MechScope Unified Store' not in text:
    raise SystemExit('[MechScope Shell] Unified Store class/title is missing from the real MechScope GUI')

# Make the Store a true MechScope surface. Do this structurally around the
# window title instead of depending on one exact resize line from an older UI.
if marker not in text:
    title_line = '        self.setWindowTitle("MechScope Unified Store")\n'
    if title_line not in text:
        raise SystemExit('[MechScope Shell] could not locate Unified Store window title')
    inject = title_line + '''        # MECHOS_FULLSCREEN_SHELL_V1
        # The Store is a MechScope surface, not a KDE desktop window.
        self.setWindowFlag(Qt.WindowType.FramelessWindowHint, True)
        self.setWindowState(Qt.WindowState.WindowFullScreen)
        self.setModal(True)
'''
    text = text.replace(title_line, inject, 1)

# Keep normal in-shell Store navigation fullscreen. Support both compact and
# spaced formatting used by different generated MechScope revisions.
if 'dialog=UnifiedStore(self)\n        dialog.showFullScreen()' not in text:
    candidates = (
        'dialog=UnifiedStore(self)\n        dialog.exec()',
        'dialog = UnifiedStore(self)\n        dialog.exec()',
        'dialog=UnifiedStore(self)\n        dialog.exec_()',
        'dialog = UnifiedStore(self)\n        dialog.exec_()',
    )
    replaced = False
    for old in candidates:
        if old in text:
            first, second = old.split('\n', 1)
            text = text.replace(old, first + '\n        dialog.showFullScreen()\n        ' + second.lstrip(), 1)
            replaced = True
            break
    if not replaced:
        # If a newer UI already launches the Store by another full-screen path,
        # accept it rather than failing the ISO build on a cosmetic text drift.
        block_start = text.find('    def open_store(self):')
        if block_start != -1:
            block_end = text.find('\n    def ', block_start + 5)
            block = text[block_start:block_end if block_end != -1 else len(text)]
            if 'showFullScreen' not in block and 'WindowFullScreen' not in block:
                raise SystemExit('[MechScope Shell] open_store exists but has no recognized fullscreen launch path')

# Standalone --store testing should use the same console-style surface.
text = text.replace(
    'dialog=UnifiedStore(); dialog.showMaximized(); sys.exit(app.exec())',
    'dialog=UnifiedStore(); dialog.showFullScreen(); sys.exit(app.exec())',
)
text = text.replace(
    'dialog = UnifiedStore(); dialog.showMaximized(); sys.exit(app.exec())',
    'dialog = UnifiedStore(); dialog.showFullScreen(); sys.exit(app.exec())',
)

if marker not in text:
    raise SystemExit('[MechScope Shell] fullscreen Store marker was not installed')
if 'FramelessWindowHint' not in text:
    raise SystemExit('[MechScope Shell] Store is not frameless')
if 'dialog.showFullScreen()' not in text and 'dialog.showFullScreen();' not in text:
    raise SystemExit('[MechScope Shell] Store has no fullscreen launch call')

path.write_text(text, encoding='utf-8')
PY

  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$mechscope" \
    || fail "MechScope Python validation failed: $mechscope"
}

patch_legacy_fallback_if_present() {
  local session="$1"
  [ -f "$session" ] || return 0

  # Older generated gaming-session revisions had their own Plasma fallback.
  # Patch it when present. Newer builds replace this session later with the
  # persistent-session gaming layer, so absence of this exact legacy block is
  # not an error.
  python3 - "$session" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
marker = '# MECHOS_PLASMA_FALLBACK_SHELL_V1'

if marker in text:
    raise SystemExit(0)

old = '''  (
    sleep 4
    echo "===== MechScope fallback $(date -Is) =====" >>"$MECHSCOPE_LOG"
    /usr/local/bin/mechscope >>"$MECHSCOPE_LOG" 2>&1
  ) &
'''
new = '''  (
    sleep 4
    # MECHOS_PLASMA_FALLBACK_SHELL_V1
    # Plasma supplies the compositor only. Hide its shell while MechScope owns
    # Gaming Mode and restore it after the fullscreen layer exits.
    if command -v kquitapp6 >/dev/null 2>&1; then
      kquitapp6 plasmashell >/dev/null 2>&1 || true
    elif command -v kquitapp5 >/dev/null 2>&1; then
      kquitapp5 plasmashell >/dev/null 2>&1 || true
    else
      pkill -x plasmashell >/dev/null 2>&1 || true
    fi

    echo "===== MechScope fallback $(date -Is) =====" >>"$MECHSCOPE_LOG"
    /usr/local/bin/mechscope >>"$MECHSCOPE_LOG" 2>&1

    if command -v plasmashell >/dev/null 2>&1 && ! pgrep -x plasmashell >/dev/null 2>&1; then
      nohup plasmashell --replace >>"$MECHSCOPE_LOG" 2>&1 &
    fi
  ) &
'''
if old in text:
    text = text.replace(old, new, 1)
    path.write_text(text, encoding='utf-8')
PY

  bash -n "$session" || fail "gaming-session shell validation failed: $session"
}

patch_tree() {
  local tree="$1"
  local mechscope
  mechscope="$(resolve_mechscope_target "$tree")"
  local session="$tree/usr/local/bin/mechos-gaming-session"

  [ -f "$mechscope" ] || fail "real MechScope GUI missing in tree: $tree"
  patch_mechscope_gui "$mechscope"
  patch_legacy_fallback_if_present "$session"
  chmod 755 "$mechscope"

  grep -Fq 'MECHOS_FULLSCREEN_SHELL_V1' "$mechscope" \
    || fail "full-screen Store marker is missing from $mechscope"
  grep -Fq 'FramelessWindowHint' "$mechscope" \
    || fail "Store is not frameless in $mechscope"
  grep -Fq 'showFullScreen' "$mechscope" \
    || fail "Store is not forced full-screen in $mechscope"

  log "patched real MechScope GUI: $mechscope"
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

log "MechScope owns Gaming Mode and the Unified Store remains a frameless fullscreen MechScope surface"
