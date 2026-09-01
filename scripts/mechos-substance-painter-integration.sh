#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
PAYLOAD="$ROOT/usr/share/mechos/install-payload"
ARCHIVE="$PAYLOAD/mechos-rootfs.tar.zst"

log() { printf '[MechOS Substance Painter] %s\n' "$*"; }
fail() { printf '[MechOS Substance Painter] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Substance Painter] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"

patch_creator_mode() {
  local tree="$1"
  local public="$tree/usr/local/bin/mechos-creator-mode"
  local real="$tree/usr/local/bin/mechos-creator-mode.real"
  local target="$public"

  [ -f "$public" ] || fail "Creator Mode launcher is missing: $public"
  if [ -f "$real" ]; then
    target="$real"
  fi

  python3 - "$target" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = "# MECHOS_SUBSTANCE_PAINTER_STORE_V1"

if marker in text:
    raise SystemExit(0)

required = [
    'PRESET_FILE=CONFIG_DIR/"creator-preset.json"',
    '("Blender","blender","3D Modeling & Animation","native"),',
    'if self.info[3] in ("vendor","setup"): return self.info[3]',
    'elif st=="setup": self.state.setText("CREATOR SETUP"); self.button.setText("Setup")',
    'if self.appid=="vrchat": self.owner.vrchat(); return',
    '("⚒  Tools",lambda:self.catalog("CREATOR TOOLS",["blender","krita","obs","kdenlive","audacity","lmms","vscode","gitkraken"])),',
]
for token in required:
    if token not in text:
        raise SystemExit(f"Creator Mode integration point not found in {path}: {token}")

# Keep the Steam application id in one explicit place so future yearly Painter
# versions can be updated without changing the UI logic.
text = text.replace(
    'PRESET_FILE=CONFIG_DIR/"creator-preset.json"\n',
    'PRESET_FILE=CONFIG_DIR/"creator-preset.json"\n'
    'SUBSTANCE_STEAM_APPID="4329260"\n',
    1,
)

# Add Painter to the individual Creator Mode app catalog. It is intentionally a
# Steam storefront entry rather than a bundled package because Adobe distributes
# the Linux build through Steam and the license remains between the user/Steam/Adobe.
text = text.replace(
    '("Blender","blender","3D Modeling & Animation","native"),\n',
    '("Blender","blender","3D Modeling & Animation","native"),\n'
    '("Substance 3D Painter 2026","substance-painter","Professional 3D texturing • Steam Linux edition","steam"),\n',
    1,
)

# Steam storefront cards do not use the native/Flatpak installer helper.
text = text.replace(
    'if self.info[3] in ("vendor","setup"): return self.info[3]\n',
    'if self.info[3] in ("vendor","setup","steam"): return self.info[3]\n',
    1,
)

text = text.replace(
    'elif st=="setup": self.state.setText("CREATOR SETUP"); self.button.setText("Setup")\n',
    'elif st=="setup": self.state.setText("CREATOR SETUP"); self.button.setText("Setup")\n'
    '        elif st=="steam": self.state.setText("STEAM • LINUX"); self.button.setText("Open in Steam")\n',
    1,
)

text = text.replace(
    'if self.appid=="vrchat": self.owner.vrchat(); return\n',
    'if self.appid=="vrchat": self.owner.vrchat(); return\n'
    '        if self.appid=="substance-painter": open_url(f"steam://store/{SUBSTANCE_STEAM_APPID}"); return\n',
    1,
)

# Also surface Painter in Creator Tools while App Store continues to show every
# CATALOG entry automatically.
text = text.replace(
    '("⚒  Tools",lambda:self.catalog("CREATOR TOOLS",["blender","krita","obs","kdenlive","audacity","lmms","vscode","gitkraken"])),',
    '("⚒  Tools",lambda:self.catalog("CREATOR TOOLS",["blender","substance-painter","krita","obs","kdenlive","audacity","lmms","vscode","gitkraken"])),',
    1,
)

lines = text.splitlines(True)
insert_at = 1 if lines and lines[0].startswith("#!") else 0
lines.insert(insert_at, marker + "\n")
path.write_text("".join(lines), encoding="utf-8")
PY

  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$target"
  grep -Fq '# MECHOS_SUBSTANCE_PAINTER_STORE_V1' "$target" || fail "Painter store marker is missing: $target"
  grep -Fq 'Substance 3D Painter 2026' "$target" || fail "Painter catalog entry is missing: $target"
  grep -Fq 'steam://store/{SUBSTANCE_STEAM_APPID}' "$target" || fail "Painter Steam launcher is missing: $target"
  grep -Fq 'SUBSTANCE_STEAM_APPID="4329260"' "$target" || fail "Painter Steam app id is missing: $target"
  log "Creator Mode store patched: $target"
}

# Patch the Live tree.
patch_creator_mode "$ROOT"

# Keep the installed-system payload identical to the Live Creator Mode catalog.
if [ -s "$ARCHIVE" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  tar --zstd -xf "$ARCHIVE" -C "$tmp"
  patch_creator_mode "$tmp"
  new_archive="$ARCHIVE.substance-painter"
  tar --zstd -cpf "$new_archive" -C "$tmp" .
  mv -f "$new_archive" "$ARCHIVE"
  rm -rf "$tmp"
  trap - EXIT
else
  fail "installed-system payload archive is missing: $ARCHIVE"
fi

log "Substance 3D Painter 2026 added to Creator Mode App Store and Creator Tools"
