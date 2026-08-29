#!/usr/bin/env bash
set -Eeuo pipefail
BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$BASE/overlay/rootfs"

required=(
  "$BASE/kiwi/mechos.xml"
  "$ROOT/usr/local/bin/mechscope-session"
  "$ROOT/usr/local/bin/mechos-install"
  "$ROOT/usr/local/bin/mechos-live-welcome"
  "$ROOT/usr/local/bin/mechos-live-shortcuts"
  "$ROOT/usr/local/bin/mechos-firstboot"
  "$ROOT/usr/local/lib/mechos/runtime.sh"
  "$ROOT/usr/share/applications/mechos-install.desktop"
  "$ROOT/etc/xdg/autostart/mechos-live-welcome.desktop"
  "$ROOT/usr/share/wayland-sessions/mechscope.desktop"
  "$ROOT/etc/systemd/system/mechos-firstboot.service"
)
for f in "${required[@]}"; do
  [[ -f "$f" ]] || { echo "Missing: $f" >&2; exit 1; }
done

grep -q 'anaconda-live' "$BASE/kiwi/mechos.xml"
grep -q 'anaconda-webui' "$BASE/kiwi/mechos.xml"
grep -q 'gamescope' "$BASE/kiwi/mechos.xml"
grep -q 'lutris' "$BASE/kiwi/mechos.xml"
grep -q 'mechos_is_live' "$ROOT/usr/local/bin/mechscope-session"
grep -q '/usr/bin/liveinst' "$ROOT/usr/local/bin/mechos-install"
grep -q 'mechos_is_live && exit 0' "$ROOT/usr/local/bin/mechos-firstboot"
grep -q 'ConditionPathExists=!/run/initramfs/live' "$ROOT/etc/systemd/system/mechos-firstboot.service"
grep -q 'Before=sddm.service' "$ROOT/etc/systemd/system/mechos-firstboot.service"
grep -q 'Install MechOS' "$ROOT/usr/share/applications/mechos-install.desktop"
grep -q -- '--branch f44' "$BASE/scripts/prepare-source.sh"
grep -q 'Refusing to build from another release' "$BASE/scripts/prepare-source.sh"

for f in "$ROOT"/usr/local/bin/* "$ROOT"/usr/local/lib/mechos/*.sh "$BASE"/*.sh "$BASE"/scripts/*.sh; do
  [[ -f "$f" ]] || continue
  bash -n "$f"
done
python3 -m py_compile "$BASE/scripts/patch-fedora-kiwi.py"
python3 - <<PY
import xml.etree.ElementTree as ET
ET.parse(r"$BASE/kiwi/mechos.xml")
print("MechOS KIWI component XML parses")
PY

count="$(find "$ROOT/usr/share/backgrounds/mechos" -maxdepth 1 -type f -name 'mechos-wallpaper-*.jpg' | wc -l)"
[[ "$count" -eq 19 ]] || { echo "Expected 19 wallpapers, got $count" >&2; exit 1; }
unique="$(sha256sum "$ROOT"/usr/share/backgrounds/mechos/mechos-wallpaper-*.jpg | awk '{print $1}' | sort -u | wc -l)"
[[ "$unique" -eq 19 ]] || { echo "Expected 19 distinct wallpapers, got $unique" >&2; exit 1; }
for w in "$ROOT"/usr/share/backgrounds/mechos/mechos-wallpaper-*.jpg; do
  file "$w" | grep -q '1920x1080' || { echo "Unexpected wallpaper dimensions: $w" >&2; exit 1; }
done

echo "MechOS 0.3.2 static validation passed. Wallpapers: $count distinct 1920x1080 images."
