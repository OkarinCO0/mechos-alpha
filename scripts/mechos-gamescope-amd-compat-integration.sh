#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
PAYLOAD="$ROOT/usr/share/mechos/install-payload"
ARCHIVE="$PAYLOAD/mechos-rootfs.tar.zst"

log() { printf '[MechOS Gamescope Universal GPU] %s\n' "$*"; }
fail() { printf '[MechOS Gamescope Universal GPU] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Gamescope Universal GPU] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"

install_selector() {
  local tree="$1"
  local bin="$tree/usr/local/bin"
  mkdir -p "$bin"

  cat > "$bin/mechos-gamescope-gpu" <<'GPU_EOF'
#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

VENDOR_NAMES = {
    "1002": "amd",
    "8086": "intel",
    "10de": "nvidia",
}
VENDOR_RANK = {"nvidia": 30, "amd": 20, "intel": 10, "unknown": 0}


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8").strip().lower()
    except OSError:
        return ""


def drm_devices() -> list[dict]:
    devices: list[dict] = []
    for card in sorted(Path("/sys/class/drm").glob("card[0-9]*")):
        dev = card / "device"
        if not dev.exists():
            continue
        vendor_id = read_text(dev / "vendor").removeprefix("0x").zfill(4)
        device_id = read_text(dev / "device").removeprefix("0x").zfill(4)
        vendor = VENDOR_NAMES.get(vendor_id, "unknown")
        if vendor == "unknown" or not device_id:
            continue
        try:
            pci = dev.resolve().name
        except OSError:
            pci = ""
        devices.append({
            "card": card.name,
            "vendor": vendor,
            "vendor_id": vendor_id,
            "device_id": device_id,
            "pci": pci,
            "boot_vga": read_text(dev / "boot_vga") == "1",
            "vulkan": False,
            "device_type": "",
            "name": "",
        })
    return devices


def vulkan_devices() -> list[dict]:
    try:
        result = subprocess.run(
            ["vulkaninfo", "--summary"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return []

    out: list[dict] = []
    current: dict | None = None
    for raw in result.stdout.splitlines():
        line = raw.strip()
        if re.match(r"^GPU[0-9]+:", line):
            if current:
                out.append(current)
            current = {}
            continue
        if current is None:
            continue
        match = re.match(r"vendorID\s*=\s*0x([0-9a-fA-F]+)", line)
        if match:
            current["vendor_id"] = match.group(1).lower().zfill(4)
            continue
        match = re.match(r"deviceID\s*=\s*0x([0-9a-fA-F]+)", line)
        if match:
            current["device_id"] = match.group(1).lower().zfill(4)
            continue
        match = re.match(r"deviceType\s*=\s*(.+)", line)
        if match:
            current["device_type"] = match.group(1).strip()
            continue
        match = re.match(r"deviceName\s*=\s*(.+)", line)
        if match:
            current["name"] = match.group(1).strip()
    if current:
        out.append(current)
    return out


def enrich(cards: list[dict]) -> None:
    vk_map = {
        (item.get("vendor_id", ""), item.get("device_id", "")): item
        for item in vulkan_devices()
    }
    for card in cards:
        match = vk_map.get((card["vendor_id"], card["device_id"]))
        if not match:
            continue
        card["vulkan"] = True
        card["device_type"] = match.get("device_type", "")
        card["name"] = match.get("name", "")


def score(card: dict, requested: str) -> int:
    if requested not in {"", "auto"} and card["vendor"] != requested:
        return -10000
    value = VENDOR_RANK.get(card["vendor"], 0)
    if card.get("vulkan"):
        value += 50
    dtype = card.get("device_type", "")
    if "DISCRETE_GPU" in dtype:
        value += 100
    elif "INTEGRATED_GPU" in dtype:
        value += 10
    if card.get("boot_vga"):
        value += 5
    return value


def choose(requested: str) -> tuple[dict | None, list[dict]]:
    cards = drm_devices()
    enrich(cards)
    if not cards:
        return None, cards
    ranked = sorted(cards, key=lambda card: score(card, requested), reverse=True)
    if ranked and score(ranked[0], requested) > -10000:
        return ranked[0], cards
    ranked = sorted(cards, key=lambda card: score(card, "auto"), reverse=True)
    return ranked[0] if ranked else None, cards


def quote(value: str) -> str:
    return "'" + value.replace("'", "'\"'\"'") + "'"


def main() -> int:
    command = sys.argv[1] if len(sys.argv) > 1 else "select"
    requested = (os.environ.get("MECHOS_GAMESCOPE_GPU") or "auto").strip().lower()
    if command == "select" and len(sys.argv) > 2:
        requested = sys.argv[2].strip().lower()

    selected, cards = choose(requested)

    if command == "json":
        print(json.dumps({"requested": requested, "selected": selected, "devices": cards}, indent=2))
        return 0 if selected else 1

    if command == "status":
        if not selected:
            print("No supported AMD, Intel, or NVIDIA GPU was detected.")
            return 1
        label = selected.get("name") or f"{selected['vendor_id']}:{selected['device_id']}"
        print(f"{selected['vendor']} {label} ({selected['vendor_id']}:{selected['device_id']})")
        return 0

    if command != "select":
        print("Usage: mechos-gamescope-gpu {select [auto|amd|intel|nvidia]|status|json}", file=sys.stderr)
        return 2

    if not selected:
        return 1

    print(f"MECHOS_GPU_VENDOR={quote(selected['vendor'])}")
    print(f"MECHOS_GPU_VK_ID={quote(selected['vendor_id'] + ':' + selected['device_id'])}")
    print(f"MECHOS_GPU_CARD={quote(selected['card'])}")
    print(f"MECHOS_GPU_PCI={quote(selected.get('pci', ''))}")
    print(f"MECHOS_GPU_VULKAN={quote('1' if selected.get('vulkan') else '0')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
GPU_EOF
  chmod 755 "$bin/mechos-gamescope-gpu"
}

patch_gaming_layer() {
  local tree="$1"
  local layer="$tree/usr/local/bin/mechos-gaming-layer"

  [ -f "$layer" ] || fail "gaming layer is missing: $layer"

  python3 - "$layer" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = "# MECHOS_UNIVERSAL_GAMESCOPE_GPU_V1"
if marker in text:
    raise SystemExit(0)

start = text.find("run_mechscope() {")
end = text.find("\n}\n\nset +e\nrun_mechscope", start)
if start < 0 or end < 0:
    raise SystemExit(f"could not locate run_mechscope() in {path}")
end += 2

replacement = r'''# MECHOS_UNIVERSAL_GAMESCOPE_GPU_V1
log_graphics_state() {
  {
    printf '[Graphics] Kernel: %s\n' "$(uname -r 2>/dev/null || true)"
    lspci -nnk 2>/dev/null | grep -A3 -Ei 'VGA|3D|Display' || true
    gamescope --version 2>&1 || true
    if command -v vulkaninfo >/dev/null 2>&1; then
      timeout 5s vulkaninfo --summary 2>&1 | head -n 120 || true
    fi
    /usr/local/bin/mechos-gamescope-gpu json 2>&1 || true
  } >>"$LOG_FILE"
}

quick_exit_without_mode_request() {
  local started="$1"
  local ended elapsed
  ended="$(date +%s)"
  elapsed=$((ended - started))
  [ "$elapsed" -lt 8 ] && [ ! -s "$MODE_FILE" ]
}

load_gamescope_gpu() {
  MECHOS_GPU_VENDOR="unknown"
  MECHOS_GPU_VK_ID=""
  MECHOS_GPU_CARD=""
  MECHOS_GPU_PCI=""
  MECHOS_GPU_VULKAN="0"

  local selected
  selected="$(/usr/local/bin/mechos-gamescope-gpu select "${MECHOS_GAMESCOPE_GPU:-auto}" 2>>"$LOG_FILE" || true)"
  if [ -n "$selected" ]; then
    eval "$selected"
  fi

  printf '[MechOS] Gamescope GPU: vendor=%s vk=%s card=%s pci=%s vulkan=%s\n' \
    "$MECHOS_GPU_VENDOR" "${MECHOS_GPU_VK_ID:-auto}" "${MECHOS_GPU_CARD:-unknown}" \
    "${MECHOS_GPU_PCI:-unknown}" "$MECHOS_GPU_VULKAN" >>"$LOG_FILE"
}

prepare_vendor_environment() {
  case "$MECHOS_GPU_VENDOR" in
    nvidia)
      export __NV_PRIME_RENDER_OFFLOAD=1
      export __GLX_VENDOR_LIBRARY_NAME=nvidia
      export __VK_LAYER_NV_optimus=NVIDIA_only
      if [ -r /sys/module/nvidia_drm/parameters/modeset ]; then
        printf '[MechOS] NVIDIA DRM modeset=%s\n' "$(cat /sys/module/nvidia_drm/parameters/modeset 2>/dev/null || true)" >>"$LOG_FILE"
      fi
      ;;
    amd|intel)
      unset __NV_PRIME_RENDER_OFFLOAD __GLX_VENDOR_LIBRARY_NAME __VK_LAYER_NV_optimus 2>/dev/null || true
      ;;
  esac
}

clear_vendor_environment() {
  unset __NV_PRIME_RENDER_OFFLOAD __GLX_VENDOR_LIBRARY_NAME __VK_LAYER_NV_optimus 2>/dev/null || true
}

run_gamescope_backend() {
  local backend="$1"
  local prefer_gpu="$2"
  local started rc=0
  local -a cmd=(gamescope -e -f --mangoapp)

  started="$(date +%s)"
  if [ "$backend" != "auto" ]; then
    cmd+=(--backend "$backend")
  fi
  if [ "$prefer_gpu" = "1" ] && [ -n "${MECHOS_GPU_VK_ID:-}" ]; then
    cmd+=(--prefer-vk-device "$MECHOS_GPU_VK_ID")
  fi
  cmd+=(-- /usr/local/bin/mechscope)

  printf '[MechOS] Gamescope attempt: vendor=%s backend=%s prefer_gpu=%s vk=%s\n' \
    "$MECHOS_GPU_VENDOR" "$backend" "$prefer_gpu" "${MECHOS_GPU_VK_ID:-auto}" >>"$LOG_FILE"

  set +e
  "${cmd[@]}" >>"$LOG_FILE" 2>&1
  rc=$?
  set -e

  if [ "$rc" -eq 0 ] && quick_exit_without_mode_request "$started"; then
    printf '[MechOS] Gamescope closed in under 8 seconds without a mode request; treating as startup failure.\n' >>"$LOG_FILE"
    rc=75
  fi
  return "$rc"
}

run_direct_mechscope() {
  local started rc=0
  started="$(date +%s)"
  printf '[MechOS] Starting direct fullscreen MechScope recovery layer.\n' >>"$LOG_FILE"
  set +e
  /usr/local/bin/mechscope >>"$LOG_FILE" 2>&1
  rc=$?
  set -e

  if [ "$rc" -eq 0 ] && quick_exit_without_mode_request "$started"; then
    printf '[MechOS] Direct MechScope closed in under 8 seconds without a mode request.\n' >>"$LOG_FILE"
    rc=75
  fi
  return "$rc"
}

run_mechscope() {
  local rc=0

  log_graphics_state
  load_gamescope_gpu
  prepare_vendor_environment

  if command -v gamescope >/dev/null 2>&1 && [ "${MECHOS_DISABLE_GAMESCOPE:-0}" != "1" ]; then
    if run_gamescope_backend auto 1; then
      return 0
    fi
    rc=$?
    printf '[MechOS] Preferred-GPU Gamescope failed rc=%s.\n' "$rc" >>"$LOG_FILE"

    if [ "$MECHOS_GPU_VENDOR" = "nvidia" ]; then
      if run_gamescope_backend sdl 1; then
        return 0
      fi
      rc=$?
      printf '[MechOS] NVIDIA SDL Gamescope failed rc=%s.\n' "$rc" >>"$LOG_FILE"
    else
      if run_gamescope_backend wayland 1; then
        return 0
      fi
      rc=$?
      printf '[MechOS] Wayland Gamescope failed rc=%s.\n' "$rc" >>"$LOG_FILE"

      if run_gamescope_backend sdl 1; then
        return 0
      fi
      rc=$?
      printf '[MechOS] SDL Gamescope failed rc=%s.\n' "$rc" >>"$LOG_FILE"
    fi

    clear_vendor_environment
    if run_gamescope_backend auto 0; then
      return 0
    fi
    rc=$?
    printf '[MechOS] Generic Gamescope retry failed rc=%s; using direct MechScope fallback.\n' "$rc" >>"$LOG_FILE"
  fi

  run_direct_mechscope
}
'''

text = text[:start] + replacement + text[end:]
path.write_text(text, encoding="utf-8")
PY

  chmod 755 "$layer"
  bash -n "$layer" || fail "gaming-layer syntax failed after universal GPU patch"
  grep -Fq '# MECHOS_UNIVERSAL_GAMESCOPE_GPU_V1' "$layer" || fail "universal GPU marker is missing"
  grep -Fq -- '--prefer-vk-device "$MECHOS_GPU_VK_ID"' "$layer" || fail "Vulkan GPU selection is missing"
  grep -Fq 'run_gamescope_backend auto 0' "$layer" || fail "generic recovery attempt is missing"
}

validate_tree() {
  local tree="$1"
  [ -x "$tree/usr/local/bin/mechos-gamescope-gpu" ] || fail "GPU selector is missing"
  [ -x "$tree/usr/local/bin/mechos-gaming-layer" ] || fail "gaming layer is missing"
  python3 - "$tree/usr/local/bin/mechos-gamescope-gpu" <<'PY'
import ast
import pathlib
import sys
ast.parse(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
PY
  bash -n "$tree/usr/local/bin/mechos-gaming-layer" || fail "gaming layer shell syntax failed"
}

patch_tree() {
  local tree="$1"
  install_selector "$tree"
  patch_gaming_layer "$tree"
  validate_tree "$tree"
}

patch_tree "$ROOT"

if [ -s "$ARCHIVE" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  tar --zstd -xf "$ARCHIVE" -C "$tmp"
  patch_tree "$tmp"
  new_archive="$ARCHIVE.gamescope-universal-gpu"
  tar --zstd -cpf "$new_archive" -C "$tmp" .
  mv -f "$new_archive" "$ARCHIVE"
  rm -rf "$tmp"
  trap - EXIT
fi

log "AMD, Intel and NVIDIA auto-selection plus Gamescope recovery applied"
