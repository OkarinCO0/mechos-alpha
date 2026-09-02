#!/usr/bin/env bash
set -Eeuo pipefail

BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INTEGRATION="$BASE/scripts/mechos-gamescope-amd-compat-integration.sh"
GPU_SETUP="$BASE/overlay/rootfs/usr/local/bin/mechos-gpu-setup"
PATCHER="$BASE/scripts/patch-mechos-safe-mode-switching.py"
BUILDER="$BASE/scripts/build-mechos-archiso.sh"
WORKFLOW="$BASE/.github/workflows/build-mechos.yml"

fail() {
  echo "MechOS universal Gamescope validation error: $*" >&2
  exit 1
}

for file in "$INTEGRATION" "$GPU_SETUP" "$PATCHER" "$BUILDER" "$WORKFLOW"; do
  [[ -f "$file" ]] || fail "missing file: $file"
done

bash -n "$INTEGRATION" || fail "Gamescope integration shell syntax failed"
bash -n "$GPU_SETUP" || fail "GPU setup shell syntax failed"

grep -Fq 'MECHOS_UNIVERSAL_GAMESCOPE_GPU_V1' "$INTEGRATION" || fail "universal runtime marker missing"
grep -Fq -- '--prefer-vk-device "$MECHOS_GPU_VK_ID"' "$INTEGRATION" || fail "Gamescope Vulkan-device selection missing"
grep -Fq '"1002": "amd"' "$INTEGRATION" || fail "AMD selector missing"
grep -Fq '"8086": "intel"' "$INTEGRATION" || fail "Intel selector missing"
grep -Fq '"10de": "nvidia"' "$INTEGRATION" || fail "NVIDIA selector missing"
grep -Fq '__NV_PRIME_RENDER_OFFLOAD=1' "$INTEGRATION" || fail "NVIDIA PRIME hint missing"
grep -Fq 'run_gamescope_backend sdl 1' "$INTEGRATION" || fail "SDL recovery path missing"
grep -Fq 'run_gamescope_backend auto 0' "$INTEGRATION" || fail "generic Gamescope recovery path missing"
grep -Fq 'mechos-gamescope-amd-compat-integration.sh final' "$PATCHER" || fail "universal Gamescope integration is not wired into the cumulative patcher"
grep -Fq 'patch-mechos-safe-mode-switching.py' "$WORKFLOW" || fail "cloud build does not apply the mode/Gamescope patcher"

for pkg in gamescope vulkan-tools vulkan-radeon lib32-vulkan-radeon vulkan-intel lib32-vulkan-intel nvidia-utils lib32-nvidia-utils; do
  grep -qx "$pkg" "$BUILDER" || fail "required GPU/Gamescope package is not in the ArchISO builder: $pkg"
done

grep -Fq 'if grep -qi nvidia' "$GPU_SETUP" || fail "GPU setup does not detect NVIDIA"
grep -Fq "if grep -Eqi 'AMD|ATI|Advanced Micro Devices'" "$GPU_SETUP" || fail "GPU setup does not detect AMD"
grep -Fq 'if grep -qi intel' "$GPU_SETUP" || fail "GPU setup does not detect Intel"
grep -Fq 'options nvidia_drm modeset=1' "$GPU_SETUP" || fail "NVIDIA DRM/KMS configuration missing"

python3 - "$INTEGRATION" <<'PY'
import ast
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(
    r"cat > \"\$bin/mechos-gamescope-gpu\" <<'GPU_EOF'\n(?P<body>.*?)\nGPU_EOF",
    text,
    flags=re.DOTALL,
)
if not match:
    raise SystemExit("MechOS universal Gamescope validation error: embedded GPU selector not found")
ast.parse(match.group("body"), filename="mechos-gamescope-gpu")
PY

echo 'MechOS universal AMD/Intel/NVIDIA Gamescope validation passed.'
