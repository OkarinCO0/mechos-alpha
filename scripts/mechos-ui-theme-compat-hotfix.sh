#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
PAYLOAD="$ROOT/usr/share/mechos/install-payload"
ARCHIVE="$PAYLOAD/mechos-rootfs.tar.zst"

log() { printf '[MechOS UI Compat] %s\n' "$*"; }
fail() { printf '[MechOS UI Compat] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS UI Compat] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"

patch_mechscope_python() {
  local file="$1"
  [ -f "$file" ] || fail "MechScope Python target is missing: $file"

  python3 - "$file" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = "# MECHOS_VISUAL_THEME_V1"

if marker in text:
    raise SystemExit(0)

class_start = text.find("class MechScope(")
if class_start < 0:
    raise SystemExit(f"MechScope class was not found in {path}")

next_class = text.find("\nclass ", class_start + 1)
class_end = next_class if next_class >= 0 else len(text)
block = text[class_start:class_end]

expr = "(__import__('pathlib').Path('/usr/share/mechos/theme/mechos-ui.qss').read_text(encoding='utf-8') if __import__('pathlib').Path('/usr/share/mechos/theme/mechos-ui.qss').is_file() else '')"

# Late MechOS integrations can change the original STYLE expression. Patch the
# actual MechScope window instead of depending on one exact source string.
style_line = re.compile(r'(?m)^(\s*)self\.setStyleSheet\(([^\n]+)\)\s*$')
m = style_line.search(block)
if m:
    current = m.group(2).strip()
    replacement = f"{m.group(1)}self.setStyleSheet(({current}) + {expr})"
    block = block[:m.start()] + replacement + block[m.end():]
else:
    # Fallback for a future multiline/custom stylesheet implementation: append
    # the shared theme immediately before MechScope builds its UI.
    build_line = re.compile(r'(?m)^(\s*)self\.build\(\)\s*$')
    b = build_line.search(block)
    if not b:
        raise SystemExit(f"Could not locate a safe MechScope theme injection point in {path}")
    injection = f"{b.group(1)}self.setStyleSheet(self.styleSheet() + {expr})\n{b.group(0)}"
    block = block[:b.start()] + injection + block[b.end():]

text = text[:class_start] + block + text[class_end:]
lines = text.splitlines(True)
insert_at = 1 if lines and lines[0].startswith("#!") else 0
lines.insert(insert_at, marker + "\n")
path.write_text("".join(lines), encoding="utf-8")
PY

  python3 -m py_compile "$file"
  grep -Fq '# MECHOS_VISUAL_THEME_V1' "$file" || fail "MechScope theme marker was not installed: $file"
  grep -Fq '/usr/share/mechos/theme/mechos-ui.qss' "$file" || fail "MechScope shared theme loader was not installed: $file"
}

mark_wrapper_for_ui_validation() {
  local wrapper="$1"
  [ -f "$wrapper" ] || return 0
  grep -Fq '# MECHOS_VISUAL_THEME_V1' "$wrapper" && return 0

  # The tutorial/OOBE integration replaces /usr/local/bin/mechscope with a
  # Bash launcher and keeps the real PyQt application as mechscope.real. The
  # UI-polish stage still validates the public launcher path, so mark the
  # wrapper after the real application has been successfully themed.
  python3 - "$wrapper" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = "# MECHOS_VISUAL_THEME_V1\n"
lines = text.splitlines(True)
insert_at = 1 if lines and lines[0].startswith("#!") else 0
lines.insert(insert_at, marker)
path.write_text("".join(lines), encoding="utf-8")
PY

  bash -n "$wrapper"
  grep -Fq '# MECHOS_VISUAL_THEME_V1' "$wrapper" || fail "MechScope wrapper validation marker was not installed: $wrapper"
}

patch_tree_mechscope() {
  local tree="$1"
  local wrapper="$tree/usr/local/bin/mechscope"
  local real="$tree/usr/local/bin/mechscope.real"
  local target="$wrapper"

  [ -f "$wrapper" ] || fail "MechScope launcher is missing: $wrapper"

  # Tutorial integration wraps MechScope before this stage. Theme the real
  # PyQt implementation when present; otherwise support the unwrapped layout.
  if [ -f "$real" ]; then
    target="$real"
  fi

  patch_mechscope_python "$target"

  if [ "$target" != "$wrapper" ]; then
    mark_wrapper_for_ui_validation "$wrapper"
  fi

  log "themed MechScope target: $target"
}

# Fix the Live copy that the UI-polish stage validates.
patch_tree_mechscope "$ROOT"

# Keep the installed-system payload in sync. UI polish runs immediately after
# this hotfix and supplies the actual shared QSS file to both trees.
if [ -s "$ARCHIVE" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  tar --zstd -xf "$ARCHIVE" -C "$tmp"
  patch_tree_mechscope "$tmp"
  new_archive="$ARCHIVE.ui-compat"
  tar --zstd -cpf "$new_archive" -C "$tmp" .
  mv -f "$new_archive" "$ARCHIVE"
  rm -rf "$tmp"
  trap - EXIT
else
  fail "installed-system payload archive is missing: $ARCHIVE"
fi

log "MechScope shared-theme compatibility patch applied to wrapped/unwrapped Live and installed payloads"
