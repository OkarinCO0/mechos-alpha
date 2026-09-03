#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"

log() { printf '[MechOS Final Payload] %s\n' "$*"; }
fail() { printf '[MechOS Final Payload] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Final Payload] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs missing"
[ -s "$ARCHIVE" ] || fail "installed payload archive missing"

STAGE="$(mktemp -d /tmp/mechos-final-payload.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

tar --zstd -xpf "$ARCHIVE" -C "$STAGE"

overlay_path() {
  local rel="$1"
  local src="$ROOT$rel"
  [ -e "$src" ] || return 0
  mkdir -p "$STAGE$(dirname "$rel")"
  rm -rf "$STAGE$rel"
  cp -a "$src" "$STAGE$rel"
}

# Final MechOS-owned runtime. Overlay the finished Live/reference copies after
# every late integration so the installed system cannot retain an older UI.
for rel in \
  /usr/local/bin/mechscope \
  /usr/local/bin/mechscope.real \
  /usr/local/bin/mechos-creator-mode \
  /usr/local/bin/mechos-creator-mode.real \
  /usr/local/bin/mechos-performance-center \
  /usr/local/bin/mechos-update-center \
  /usr/local/bin/mechos-update-helper \
  /usr/local/bin/mechos-update \
  /usr/local/bin/mechos-quick-actions \
  /usr/local/bin/mechos-quick-actions-daemon \
  /usr/local/bin/mechos-stream-center \
  /usr/local/bin/mechos-stream-control \
  /usr/local/bin/mechos-recovery-center \
  /usr/local/bin/mechos-recovery-helper \
  /usr/local/bin/mechos-hardware-scan \
  /usr/local/bin/mechos-gaming-session \
  /usr/local/bin/mechos-creator-session \
  /usr/local/bin/mechos-return-to-mechscope \
  /usr/local/bin/mechos-session-select \
  /usr/local/bin/mechos-gpu-setup \
  /usr/local/bin/mechos-firstboot \
  /usr/local/bin/mechos-oobe \
  /usr/local/libexec/mechos-oobe-apply \
  /usr/local/bin/mechos-creator-app \
  /usr/local/libexec/mechos-creator-app-installer \
  /usr/share/mechos \
  /usr/share/applications/mechscope.desktop \
  /usr/share/applications/mechos-creator-mode.desktop \
  /usr/share/applications/mechos-performance-center.desktop \
  /usr/share/applications/mechos-update-center.desktop \
  /usr/share/applications/mechos-recovery-center.desktop \
  /usr/share/applications/mechos-return-to-mechscope.desktop \
  /usr/share/wayland-sessions/mechos-gaming.desktop \
  /usr/share/wayland-sessions/mechos-creator.desktop \
  /etc/xdg/kdeglobals \
  /etc/xdg/kwinrc
do
  overlay_path "$rel"
done

# Preserve post-install-only files already in the archive, then rebuild with the
# exact final reference runtime overlaid above.
TMP_ARCHIVE="$ARCHIVE.tmp"
tar --zstd -cpf "$TMP_ARCHIVE" -C "$STAGE" .
mv -f "$TMP_ARCHIVE" "$ARCHIVE"

# Verify the installed system will receive v5, not an older snapshot.
tar --zstd -tf "$ARCHIVE" ./usr/share/mechos/reference-ui-v5.json >/dev/null \
  || fail "v5 manifest is missing from installed payload"
tar --zstd -tf "$ARCHIVE" ./usr/share/mechos/theme/reference-v5.qss >/dev/null \
  || fail "v5 theme is missing from installed payload"
tar --zstd -tf "$ARCHIVE" ./etc/xdg/kdeglobals >/dev/null \
  || fail "low-latency Plasma defaults are missing from installed payload"
tar --zstd -tf "$ARCHIVE" ./usr/local/bin/mechscope >/dev/null \
  || fail "final MechScope is missing from installed payload"

log "Installed payload rebuilt from the final Reference UI v5 runtime"
