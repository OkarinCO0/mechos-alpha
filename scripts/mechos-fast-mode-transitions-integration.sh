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

# Gamescope's standalone compositor expects real DRM/KMS/Vulkan hardware.
# VirtualBox (VMSVGA/VMware SVGA), VMware, QEMU/KVM virtio/QXL and software
# renderers can crash Gamescope before MechScope appears. Detect those guests
# and keep the same MechScope UI by launching it directly in the authenticated
# Plasma session. Physical AMD/Intel/NVIDIA systems continue through Gamescope.
vm_marker = "# MECHOS_VM_GAMESCOPE_FALLBACK_V1"
if vm_marker not in text:
    anchor = text.find("run_mechscope() {")
    if anchor < 0:
        raise SystemExit("[MechOS Fast Mode Switch] could not locate run_mechscope() for VM fallback")
    helper = r'''# MECHOS_VM_GAMESCOPE_FALLBACK_V1
is_virtual_gpu_environment() {
  local dmi pci modules
  dmi="$({
    cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true
    cat /sys/class/dmi/id/product_name 2>/dev/null || true
    cat /sys/class/dmi/id/board_vendor 2>/dev/null || true
  } | tr '\n' ' ')"
  pci="$(lspci -nn 2>/dev/null | grep -Ei 'VGA|3D|Display' || true)"
  modules="$(lsmod 2>/dev/null | awk '{print $1}' | tr '\n' ' ')"

  if printf '%s\n' "$dmi" | grep -Eqi \
    'virtualbox|vmware|qemu|kvm|bochs|parallels|hyper-v|microsoft corporation.*virtual|innotek'; then
    printf '[MechOS] Virtual machine detected from DMI: %s\n' "$dmi" >>"$LOG_FILE"
    return 0
  fi

  if printf '%s\n' "$pci" | grep -Eqi \
    'VMware.*SVGA|VirtualBox|Virtio.*GPU|Red Hat.*QXL|Bochs|Hyper-V|Microsoft.*Virtual'; then
    printf '[MechOS] Virtual GPU detected from PCI: %s\n' "$pci" >>"$LOG_FILE"
    return 0
  fi

  if printf '%s\n' "$modules" | grep -Eq \
    '(^| )(vmwgfx|vboxvideo|virtio_gpu|qxl|bochs_drm)( |$)'; then
    printf '[MechOS] Virtual graphics kernel driver detected.\n' >>"$LOG_FILE"
    return 0
  fi

  return 1
}

'''
    text = text[:anchor] + helper + text[anchor:]

    needle = '''  log_graphics_state &
  load_gamescope_gpu
  prepare_vendor_environment
'''
    replacement = '''  log_graphics_state &
  load_gamescope_gpu

  if is_virtual_gpu_environment; then
    clear_vendor_environment
    export MECHOS_VM_MODE=1
    export MECHOS_DISABLE_GAMESCOPE=1
    printf '[MechOS] VM-safe gaming mode: bypassing Gamescope and launching MechScope directly.\\n' >>"$LOG_FILE"
    run_direct_mechscope
    return $?
  fi

  unset MECHOS_VM_MODE 2>/dev/null || true
  prepare_vendor_environment
'''
    if needle not in text:
        raise SystemExit("[MechOS Fast Mode Switch] could not locate run_mechscope preflight for VM fallback")
    text = text.replace(needle, replacement, 1)

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
  grep -Fq '# MECHOS_VM_GAMESCOPE_FALLBACK_V1' "$layer" \
    || fail "VM Gamescope fallback marker is missing"
  grep -Fq 'VM-safe gaming mode: bypassing Gamescope' "$layer" \
    || fail "VM-safe direct MechScope fallback is missing"
  grep -Fq 'vmwgfx|vboxvideo|virtio_gpu|qxl|bochs_drm' "$layer" \
    || fail "virtual graphics driver detection is missing"
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

log "Mode transitions optimized: cached GPU selection, VM-safe Gamescope bypass, async diagnostics, non-blocking user-service handoffs and shorter stop/restart timeouts"
