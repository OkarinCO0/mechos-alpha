#!/usr/bin/env bash
set -Eeuo pipefail

MODE="${1:-}"
ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"
STAGE="/tmp/mechos-reference-v5-postinstall-root"
STATE="/tmp/mechos-reference-v5-postinstall-staged.list"

log() { printf '[MechOS Reference UI v5 Postinstall] %s\n' "$*"; }
fail() { printf '[MechOS Reference UI v5 Postinstall] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Reference UI v5 Postinstall] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ -d "$ROOT" ] || fail "ArchISO rootfs missing: $ROOT"
[ -s "$ARCHIVE" ] || fail "installed-system payload missing: $ARCHIVE"

POSTINSTALL_SURFACES=(
  /usr/local/bin/mechos-creator-mode
  /usr/local/bin/mechos-creator-mode.real
  /usr/local/bin/mechos-quick-actions
  /usr/local/bin/mechos-quick-actions.real
)

archive_has() {
  tar --zstd -tf "$ARCHIVE" ".${1}" >/dev/null 2>&1
}

case "$MODE" in
  prepare)
    rm -rf "$STAGE"
    rm -f "$STATE"
    mkdir -p "$STAGE"
    : > "$STATE"

    # Creator Mode and Quick Actions are intentionally post-install-only. For
    # the build only, materialize their installed copies into the Live tree so
    # the same v5 layout patchers can operate on them. Record only files that
    # were absent from Live so commit can remove them again before mkarchiso.
    for rel in "${POSTINSTALL_SURFACES[@]}"; do
      [ -e "$ROOT$rel" ] && continue
      archive_has "$rel" || continue
      mkdir -p "$STAGE$(dirname "$rel")" "$ROOT$(dirname "$rel")"
      tar --zstd -xpf "$ARCHIVE" -C "$STAGE" ".${rel}"
      cp -a "$STAGE$rel" "$ROOT$rel"
      printf '%s\n' "$rel" >> "$STATE"
      log "temporarily staged post-install surface: $rel"
    done

    # These are required in the installed system even though they are not Live
    # apps. Fail here rather than later with an unclear reference-surface error.
    [ -e "$ROOT/usr/local/bin/mechos-creator-mode" ] || [ -e "$ROOT/usr/local/bin/mechos-creator-mode.real" ] \
      || fail "Creator Mode is missing from both Live and installed payload"
    [ -e "$ROOT/usr/local/bin/mechos-quick-actions" ] || [ -e "$ROOT/usr/local/bin/mechos-quick-actions.real" ] \
      || fail "Quick Actions is missing from both Live and installed payload"

    log "post-install surfaces staged for Reference UI v5 patching"
    ;;

  commit)
    [ -f "$STATE" ] || fail "prepare state is missing"
    mkdir -p "$STAGE"

    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      [ -e "$ROOT$rel" ] || fail "staged surface disappeared before commit: $rel"
      mkdir -p "$STAGE$(dirname "$rel")"
      rm -rf "$STAGE$rel"
      cp -a "$ROOT$rel" "$STAGE$rel"
      rm -f "$ROOT$rel"
      log "captured patched post-install surface and removed temporary Live copy: $rel"
    done < "$STATE"

    # The final payload builder consumes STAGE after extracting the existing
    # archive. Keep this directory until mechos-finalize-install-payload.sh has
    # rebuilt the archive, then that script removes it.
    log "patched post-install surfaces ready for final payload sync"
    ;;

  *)
    fail "usage: $0 {prepare|commit}"
    ;;
esac
