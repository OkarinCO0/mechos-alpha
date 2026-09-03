#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"
POSTINSTALL_STAGE="/tmp/mechos-reference-v5-postinstall-root"
POSTINSTALL_STATE="/tmp/mechos-reference-v5-postinstall-staged.list"

log() { printf '[MechOS Final Payload] %s\n' "$*"; }
fail() { printf '[MechOS Final Payload] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Final Payload] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs missing"
[ -s "$ARCHIVE" ] || fail "installed payload archive missing"

STAGE="$(mktemp -d /tmp/mechos-final-payload.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

tar --zstd -xpf "$ARCHIVE" -C "$STAGE"

# Creator Mode and Quick Actions are post-install-only. Their v5 patchers run
# against temporary build copies, captured under POSTINSTALL_STAGE. Apply those
# patched copies to the installed tree before overlaying the true Live runtime.
if [ -d "$POSTINSTALL_STAGE" ]; then
  rsync -aHAX --numeric-ids "$POSTINSTALL_STAGE"/ "$STAGE"/
  log "merged patched post-install-only Reference UI v5 surfaces"
fi

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
# Post-install-only files are intentionally absent from Live at this point, so
# their patched copies above remain untouched.
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
  /usr/local/bin/mechos-quick-actions.real \
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

pick_surface() {
  local base="$1"
  if [ -f "$STAGE/usr/local/bin/$base.real" ]; then
    printf '%s\n' "$STAGE/usr/local/bin/$base.real"
  elif [ -f "$STAGE/usr/local/bin/$base" ]; then
    printf '%s\n' "$STAGE/usr/local/bin/$base"
  else
    return 1
  fi
}

CREATOR_FILE="$(pick_surface mechos-creator-mode)" || fail "Creator Mode missing from installed payload"
QUICK_FILE="$(pick_surface mechos-quick-actions)" || fail "Quick Actions missing from installed payload"
grep -Fq 'MECHOS_REFERENCE_CREATOR_V5' "$CREATOR_FILE" \
  || fail "Creator Mode did not receive the Reference UI v5 dashboard/store layout"
grep -Fq 'MECHOS_REFERENCE_QUICK_ACTIONS_V5' "$QUICK_FILE" \
  || fail "Quick Actions did not receive the Reference UI v5 layout"

# Rebuild the installed archive with both post-install-only and Live/reference
# surfaces synchronized to their final v5 state.
TMP_ARCHIVE="$ARCHIVE.tmp"
tar --zstd -cpf "$TMP_ARCHIVE" -C "$STAGE" .
mv -f "$TMP_ARCHIVE" "$ARCHIVE"

# Temporary copies must never leak into the Live ISO.
rm -rf "$POSTINSTALL_STAGE"
rm -f "$POSTINSTALL_STATE"
[ ! -e "$ROOT/usr/local/bin/mechos-creator-mode" ] || fail "post-install-only Creator Mode leaked into Live rootfs"
[ ! -e "$ROOT/usr/local/bin/mechos-creator-mode.real" ] || fail "post-install-only Creator Mode wrapper leaked into Live rootfs"
[ ! -e "$ROOT/usr/local/bin/mechos-quick-actions" ] || fail "post-install-only Quick Actions leaked into Live rootfs"
[ ! -e "$ROOT/usr/local/bin/mechos-quick-actions.real" ] || fail "post-install-only Quick Actions wrapper leaked into Live rootfs"

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
