#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
PAYLOAD="$ROOT/usr/share/mechos/install-payload"
ARCHIVE="$PAYLOAD/mechos-rootfs.tar.zst"
TARGET_W=1920
TARGET_H=1080

log() { printf '[MechOS Wallpapers] %s\n' "$*"; }
fail() { printf '[MechOS Wallpapers] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Wallpapers] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"

# Pillow is a build-time tool only. It is used to normalize the bundled
# wallpapers and is not added to the installed MechOS package set.
if ! python3 - <<'PY' >/dev/null 2>&1
from PIL import Image
PY
then
  command -v pacman >/dev/null 2>&1 || fail "python-pillow is missing and pacman is unavailable"
  pacman -S --needed --noconfirm python-pillow
fi

resize_tree() {
  local tree="$1"
  local dir="$tree/usr/share/backgrounds/mechos"
  [ -d "$dir" ] || fail "MechOS wallpaper directory is missing: $dir"

  python3 - "$dir" "$TARGET_W" "$TARGET_H" <<'PY'
from pathlib import Path
from PIL import Image, ImageOps
import sys

root = Path(sys.argv[1])
target = (int(sys.argv[2]), int(sys.argv[3]))
files = sorted(root.glob("mechos-wallpaper-*.jpg"))
if len(files) != 19:
    raise SystemExit(f"expected 19 MechOS wallpapers, found {len(files)} in {root}")

for path in files:
    with Image.open(path) as source:
        source = source.convert("RGB")
        if source.size == target:
            print(f"[OK] {path.name}: already {target[0]}x{target[1]}")
            continue

        # Use a center-cropped 16:9 cover fit instead of stretching the artwork.
        # This guarantees an exact 1920x1080 desktop image while preserving the
        # original aspect ratio and avoiding black bars.
        fitted = ImageOps.fit(
            source,
            target,
            method=Image.Resampling.LANCZOS,
            centering=(0.5, 0.5),
        )
        fitted.save(path, "JPEG", quality=92, optimize=True, progressive=True)
        print(f"[RESIZED] {path.name}: {source.width}x{source.height} -> {target[0]}x{target[1]}")

for path in files:
    with Image.open(path) as check:
        if check.size != target:
            raise SystemExit(f"wallpaper resolution validation failed for {path}: {check.size}")
PY
}

resize_tree "$ROOT"

# The installed-system payload is generated before this late integration. Some
# earlier payload stages intentionally copy only the default wallpaper, so do
# not assume the archive already contains the complete wallpaper collection.
# Seed the installed payload from the finalized Live wallpaper set, then run
# the same exact 1920x1080 validation on the installed copy.
if [ -s "$ARCHIVE" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  tar --zstd -xf "$ARCHIVE" -C "$tmp"

  live_wallpapers="$ROOT/usr/share/backgrounds/mechos"
  installed_wallpapers="$tmp/usr/share/backgrounds/mechos"
  mkdir -p "$installed_wallpapers"
  find "$installed_wallpapers" -maxdepth 1 -type f -name 'mechos-wallpaper-*.jpg' -delete
  cp -a "$live_wallpapers"/mechos-wallpaper-*.jpg "$installed_wallpapers"/

  resize_tree "$tmp"
  new_archive="$ARCHIVE.wallpapers-1080p"
  tar --zstd -cf "$new_archive" -C "$tmp" .
  mv -f "$new_archive" "$ARCHIVE"
  rm -rf "$tmp"
  trap - EXIT
fi

log "All 19 MechOS wallpapers normalized to 1920x1080 in Live and installed payloads"
