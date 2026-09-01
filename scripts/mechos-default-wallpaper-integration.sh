#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
PAYLOAD="$ROOT/usr/share/mechos/install-payload"
ARCHIVE="$PAYLOAD/mechos-rootfs.tar.zst"
DEFAULT_REL="/usr/share/backgrounds/mechos/mechos-wallpaper-01.jpg"
DEFAULT_SOURCE="$ROOT$DEFAULT_REL"

log() { printf '[MechOS Wallpaper] %s\n' "$*"; }
fail() { printf '[MechOS Wallpaper] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Wallpaper] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"
[ -s "$DEFAULT_SOURCE" ] || fail "default MechOS wallpaper is missing: $DEFAULT_SOURCE"
[ -s "$ARCHIVE" ] || fail "installed-system payload archive is missing: $ARCHIVE"

install_wallpaper_runtime() {
  local tree="$1"
  local source="$tree$DEFAULT_REL"
  local bin="$tree/usr/local/bin"
  local autostart="$tree/etc/xdg/autostart"
  local package="$tree/usr/share/wallpapers/MechOS"

  if [ ! -s "$source" ]; then
    mkdir -p "$(dirname "$source")"
    cp -a "$DEFAULT_SOURCE" "$source"
  fi

  mkdir -p "$bin" "$autostart" "$package/contents/images"
  cp -f "$source" "$package/contents/images/mechos-default.jpg"

  cat > "$package/metadata.json" <<'JSONEOF'
{
  "KPlugin": {
    "Id": "MechOS",
    "Name": "MechOS",
    "Description": "Default MechOS desktop wallpaper",
    "Version": "1.0",
    "License": "Proprietary"
  }
}
JSONEOF

  cat > "$bin/mechos-wallpaper-init" <<'EOF'
#!/usr/bin/env bash
set -u

WALLPAPER="/usr/share/backgrounds/mechos/mechos-wallpaper-01.jpg"
MARKER="${XDG_CONFIG_HOME:-$HOME/.config}/mechos/default-wallpaper-v1.done"

[ -s "$WALLPAPER" ] || exit 0
[ -e "$MARKER" ] && exit 0

apply_wallpaper() {
  if command -v plasma-apply-wallpaperimage >/dev/null 2>&1; then
    plasma-apply-wallpaperimage "$WALLPAPER" >/dev/null 2>&1 && return 0
  fi

  local js bus
  js="var ds=desktops(); for (var i=0;i<ds.length;i++){var d=ds[i];d.wallpaperPlugin='org.kde.image';d.currentConfigGroup=['Wallpaper','org.kde.image','General'];d.writeConfig('Image','file://$WALLPAPER');d.writeConfig('PreviewImage','file://$WALLPAPER');}"

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    for bus in qdbus6 qdbus; do
      command -v "$bus" >/dev/null 2>&1 || continue
      "$bus" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$js" >/dev/null 2>&1 && return 0
    done
    sleep 1
  done
  return 1
}

if apply_wallpaper; then
  mkdir -p "$(dirname "$MARKER")"
  printf '%s\n' "$WALLPAPER" > "$MARKER"
fi

exit 0
EOF
  chmod 755 "$bin/mechos-wallpaper-init"

  cat > "$autostart/mechos-default-wallpaper.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS Default Wallpaper
Comment=Apply the MechOS wallpaper on the first Plasma login
Exec=/usr/local/bin/mechos-wallpaper-init
OnlyShowIn=KDE;
X-KDE-autostart-after=panel
Terminal=false
NoDisplay=true
EOF

  bash -n "$bin/mechos-wallpaper-init"
  grep -Fq '/usr/share/backgrounds/mechos/mechos-wallpaper-01.jpg' "$bin/mechos-wallpaper-init" \
    || fail "wallpaper runtime does not reference the MechOS default image"
  grep -Fq 'default-wallpaper-v1.done' "$bin/mechos-wallpaper-init" \
    || fail "wallpaper runtime is not first-login-only"
  test -s "$package/contents/images/mechos-default.jpg" \
    || fail "KDE MechOS wallpaper package image is missing"
}

# Live Plasma receives the branded wallpaper and applies it once for the Live user.
install_wallpaper_runtime "$ROOT"

# The installed payload receives the same wallpaper/runtime. The per-user marker
# means the MechOS default is applied once and user wallpaper changes are preserved.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

tar --zstd -xf "$ARCHIVE" -C "$tmp"
install_wallpaper_runtime "$tmp"

new_archive="$ARCHIVE.wallpaper"
tar --zstd -cf "$new_archive" -C "$tmp" .
mv -f "$new_archive" "$ARCHIVE"
rm -rf "$tmp"
trap - EXIT

log "MechOS wallpaper 01 set as the first-login Plasma default for Live and installed systems"
