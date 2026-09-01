#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
PAYLOAD="$ROOT/usr/share/mechos/install-payload"
ARCHIVE="$PAYLOAD/mechos-rootfs.tar.zst"

log() { printf '[MechOS Return Shortcut] %s\n' "$*"; }
fail() { printf '[MechOS Return Shortcut] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Return Shortcut] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"

patch_tree() {
  local tree="$1"
  local apps="$tree/usr/share/applications"
  local launcher="$apps/mechos-return-gaming.desktop"
  local return_cmd="$tree/usr/local/bin/mechos-return-to-mechscope"
  local control="$tree/usr/local/bin/mechos-gaming-layer-control"

  [ -x "$return_cmd" ] || fail "passwordless return helper is missing: $return_cmd"
  [ -x "$control" ] || fail "gaming-layer control helper is missing: $control"
  mkdir -p "$apps"

  cat > "$launcher" <<'DESKTOP_EOF'
[Desktop Entry]
Name=Return to MechScope
Comment=Return to MechScope without logging out or requesting administrator privileges
Exec=/usr/local/bin/mechos-return-to-mechscope
Icon=applications-games
Terminal=false
Type=Application
Categories=Game;System;
StartupNotify=false
DESKTOP_EOF

  # If a desktop copy was already staged by another integration, replace it
  # with the same user-session launcher. Never route this action through
  # loginctl, sudo, pkexec, or a root system service.
  for desktop_dir in "$tree/etc/skel/Desktop" "$tree/home/mechos/Desktop"; do
    [ -d "$desktop_dir" ] || continue
    cp -f "$launcher" "$desktop_dir/mechos-return-gaming.desktop"
    chmod 755 "$desktop_dir/mechos-return-gaming.desktop" || true
  done

  grep -Fq 'Exec=/usr/local/bin/mechos-return-to-mechscope' "$launcher" \
    || fail "Return to MechScope launcher is not wired to the user-session helper"

  for file in "$launcher" "$return_cmd" "$control"; do
    if grep -Eq '(^|[[:space:]])(sudo|pkexec|loginctl)([[:space:]]|$)' "$file"; then
      fail "password/root-requiring command found in Return to MechScope path: $file"
    fi
  done
}

patch_tree "$ROOT"

if [ -s "$ARCHIVE" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  tar --zstd -xf "$ARCHIVE" -C "$tmp"
  patch_tree "$tmp"
  new_archive="$ARCHIVE.passwordless-return"
  tar --zstd -cf "$new_archive" -C "$tmp" .
  mv -f "$new_archive" "$ARCHIVE"
  rm -rf "$tmp"
  trap - EXIT
fi

log "Return to MechScope now starts the user gaming layer directly with no password prompt"
