#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"

log() { printf '[MechOS Fast Mode Switch] %s\n' "$*"; }
fail() { printf '[MechOS Fast Mode Switch] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Fast Mode Switch] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"
[ -s "$ARCHIVE" ] || fail "installed payload is missing: $ARCHIVE"

patch_tree() {
  local tree="$1"
  local layer="$tree/usr/local/bin/mechos-gaming-layer"
  local control="$tree/usr/local/bin/mechos-gaming-layer-control"
  local gaming_unit="$tree/usr/lib/systemd/user/mechos-gaming-layer.service"
  local creator_unit="$tree/usr/lib/systemd/user/mechos-creator-mode.service"

  [ -f "$layer" ] || fail "gaming layer is missing in $tree"
  [ -f "$control" ] || fail "gaming layer control is missing in $tree"
  [ -f "$gaming_unit" ] || fail "gaming-layer unit is missing in $tree"

  python3 - "$layer" "$control" <<'PY'
from pathlib import Path
import sys

layer = Path(sys.argv[1])
control = Path(sys.argv[2])

text = layer.read_text(encoding="utf-8")
marker = "# MECHOS_FAST_MODE_TRANSITIONS_V1"

if marker not in text:
    # GPU detection is stable across ordinary mode changes. Cache it using a
    # signature of the DRM vendor/device IDs plus the requested GPU preference.
    start = text.find("load_gamescope_gpu() {")
    end = text.find("\n}\n\nprepare_vendor_environment()", start)
    if start < 0 or end < 0:
        raise SystemExit("[MechOS Fast Mode Switch] could not locate load_gamescope_gpu()")
    end += 2
    replacement = r'''# MECHOS_FAST_MODE_TRANSITIONS_V1
load_gamescope_gpu() {
  MECHOS_GPU_VENDOR="unknown"
  MECHOS_GPU_VK_ID=""
  MECHOS_GPU_CARD=""
  MECHOS_GPU_PCI=""
  MECHOS_GPU_VULKAN="0"

  local cache_dir cache_file requested signature cached_signature selected
  cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/mechos"
  cache_file="$cache_dir/gamescope-gpu.env"
  requested="${MECHOS_GAMESCOPE_GPU:-auto}"
  mkdir -p "$cache_dir"

  signature="$({
    printf '%s\n' "$requested"
    for dev in /sys/class/drm/card[0-9]*/device; do
      [ -d "$dev" ] || continue
      printf '%s:%s\n' \
        "$(cat "$dev/vendor" 2>/dev/null || true)" \
        "$(cat "$dev/device" 2>/dev/null || true)"
    done
  } | sha256sum | awk '{print $1}')"

  cached_signature="$(sed -n 's/^# signature=//p' "$cache_file" 2>/dev/null | head -n1 || true)"
  if [ -n "$signature" ] && [ "$cached_signature" = "$signature" ]; then
    selected="$(grep '^MECHOS_GPU_' "$cache_file" 2>/dev/null || true)"
    printf '[MechOS] Reusing cached Gamescope GPU selection.\n' >>"$LOG_FILE"
  else
    selected="$(/usr/local/bin/mechos-gamescope-gpu select "$requested" 2>>"$LOG_FILE" || true)"
    if [ -n "$selected" ]; then
      {
        printf '# signature=%s\n' "$signature"
        printf '%s\n' "$selected"
      } >"$cache_file.tmp"
      mv -f "$cache_file.tmp" "$cache_file"
    fi
  fi

  if [ -n "$selected" ]; then
    eval "$selected"
  fi

  printf '[MechOS] Gamescope GPU: vendor=%s vk=%s card=%s pci=%s vulkan=%s\n' \
    "$MECHOS_GPU_VENDOR" "${MECHOS_GPU_VK_ID:-auto}" "${MECHOS_GPU_CARD:-unknown}" \
    "${MECHOS_GPU_PCI:-unknown}" "$MECHOS_GPU_VULKAN" >>"$LOG_FILE"
}
'''
    text = text[:start] + replacement + text[end:]

# Hardware diagnostics are useful, but they must not block the visible mode
# transition. Run them asynchronously while MechScope is already opening.
text = text.replace("  log_graphics_state\n  load_gamescope_gpu\n", "  log_graphics_state &\n  load_gamescope_gpu\n", 1)
layer.write_text(text, encoding="utf-8")

text = control.read_text(encoding="utf-8")
# systemd Type=simple is ready as soon as the process is spawned. Do not make
# the UI wait for synchronous job completion on ordinary mode changes.
text = text.replace('systemctl --user start "$UNIT"', 'systemctl --user start --no-block "$UNIT"')
text = text.replace('systemctl --user stop "$UNIT" 2>/dev/null || true', 'systemctl --user stop --no-block "$UNIT" 2>/dev/null || true')
control.write_text(text, encoding="utf-8")
PY

  sed -i \
    -e 's/^RestartSec=.*/RestartSec=0.25/' \
    -e 's/^TimeoutStopSec=.*/TimeoutStopSec=2/' \
    "$gaming_unit"

  if [ -f "$creator_unit" ]; then
    sed -i 's/^TimeoutStopSec=.*/TimeoutStopSec=2/' "$creator_unit"
  fi

  chmod 755 "$layer" "$control"
  bash -n "$layer" || fail "gaming-layer syntax failed after transition optimization"
  bash -n "$control" || fail "gaming-layer-control syntax failed after transition optimization"

  grep -Fq '# MECHOS_FAST_MODE_TRANSITIONS_V1' "$layer" \
    || fail "fast transition marker is missing"
  grep -Fq 'Reusing cached Gamescope GPU selection' "$layer" \
    || fail "GPU transition cache is missing"
  grep -Fq 'log_graphics_state &' "$layer" \
    || fail "graphics diagnostics still block MechScope startup"
  grep -Fq 'systemctl --user start --no-block "$UNIT"' "$control" \
    || fail "gaming-layer start is still blocking"
  grep -Fq 'systemctl --user stop --no-block "$UNIT"' "$control" \
    || fail "gaming-layer stop is still blocking"
  grep -Fq 'RestartSec=0.25' "$gaming_unit" \
    || fail "fast gaming-layer restart delay is missing"
  grep -Fq 'TimeoutStopSec=2' "$gaming_unit" \
    || fail "gaming-layer stop timeout is not reduced"
}

patch_tree "$ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar --zstd -xf "$ARCHIVE" -C "$tmp"
patch_tree "$tmp"
replacement="$ARCHIVE.fast-mode"
tar --zstd -cpf "$replacement" -C "$tmp" .
mv -f "$replacement" "$ARCHIVE"
rm -rf "$tmp"
trap - EXIT

log "Mode transitions optimized: cached GPU selection, async diagnostics, non-blocking user-service handoffs and shorter stop/restart timeouts"
