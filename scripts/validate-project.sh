#!/usr/bin/env bash
set -Eeuo pipefail

BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$BASE/overlay/rootfs"
WORKFLOW="$BASE/.github/workflows/build-mechos.yml"

fail() {
  echo "MechOS validation error: $*" >&2
  exit 1
}

for command_name in bash python3 file sha256sum awk grep find mktemp; do
  command -v "$command_name" >/dev/null 2>&1 || fail "missing validator command: $command_name"
done

required=(
  "$BASE/build-iso.sh"
  "$BASE/scripts/build-mechos-archiso.sh"
  "$BASE/scripts/mechos-current-integration.sh"
  "$BASE/scripts/patch-mechos-current.py"
  "$BASE/scripts/validate-project.sh"
  "$WORKFLOW"
  "$ROOT/usr/local/lib/mechos/runtime.sh"
  "$ROOT/usr/local/bin/mechscope-session"
  "$ROOT/usr/local/bin/mechos-install"
  "$ROOT/usr/local/bin/mechos-live-welcome"
  "$ROOT/usr/local/bin/mechos-firstboot"
  "$ROOT/usr/local/bin/mechos-gpu-setup"
  "$ROOT/usr/share/wayland-sessions/mechscope.desktop"
  "$ROOT/etc/systemd/system/mechos-firstboot.service"
  "$ROOT/etc/mechos/mechos.conf"
)

for path in "${required[@]}"; do
  [[ -f "$path" ]] || fail "required file is missing: $path"
done

executables=(
  "$BASE/build-iso.sh"
  "$BASE/scripts/build-mechos-archiso.sh"
  "$BASE/scripts/mechos-current-integration.sh"
  "$BASE/scripts/prepare-source.sh"
  "$BASE/scripts/setup-build-host.sh"
  "$BASE/scripts/validate-project.sh"
)

for path in "${executables[@]}"; do
  [[ -x "$path" ]] || fail "required script is not executable: $path"
done

for path in "$BASE"/*.sh "$BASE"/scripts/*.sh; do
  [[ -f "$path" ]] || continue
  bash -n "$path" || fail "shell syntax failed: $path"
done

while IFS= read -r -d '' path; do
  if head -n 1 "$path" | grep -qE '^#!.*/(env )?bash'; then
    bash -n "$path" || fail "overlay shell syntax failed: $path"
  fi
done < <(find "$ROOT/usr/local/bin" "$ROOT/usr/local/lib" -type f -print0)

python3 - "$BASE" <<'PY'
import ast
import pathlib
import sys

base = pathlib.Path(sys.argv[1])
files = sorted((base / "scripts").glob("*.py"))
if not files:
    raise SystemExit("MechOS validation error: no Python helpers found")
for path in files:
    ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
print(f"Python syntax passed: {len(files)} files")
PY

grep -q '^#!/usr/bin/env bash$' "$BASE/build-iso.sh" || fail "build-iso.sh is not a shell program"
grep -q 'scripts/validate-project.sh' "$WORKFLOW" || fail "cloud build skips project validation"
grep -q './build-iso.sh' "$WORKFLOW" || fail "cloud build does not invoke the supported build wrapper"
grep -q 'archlinux:latest' "$BASE/build-iso.sh" || fail "build wrapper is not using the Arch Linux container"
grep -q 'scripts/build-mechos-archiso.sh' "$BASE/build-iso.sh" || fail "local builder does not invoke the ArchISO builder"
grep -q 'MECHOS_CURRENT_INTEGRATION_EARLY' "$BASE/scripts/build-mechos-archiso.sh" || fail "early cumulative integration marker is missing"
grep -q 'MECHOS_CURRENT_INTEGRATION_LATE' "$BASE/scripts/build-mechos-archiso.sh" || fail "late cumulative integration marker is missing"
grep -q 'mkarchiso' "$BASE/scripts/build-mechos-archiso.sh" || fail "ArchISO build command is missing"
grep -q 'archinstall' "$BASE/scripts/build-mechos-archiso.sh" || fail "Archinstall integration is missing"
grep -q '/run/archiso/bootmnt' "$ROOT/usr/local/lib/mechos/runtime.sh" || fail "ArchISO live detection is missing"
grep -qx 'MECHOS_BASE=Arch-Linux' "$ROOT/etc/mechos/mechos.conf" || fail "MechOS base metadata is not Arch Linux"

for legacy in \
  "$BASE/kiwi/mechos.xml" \
  "$BASE/scripts/patch-fedora-kiwi.py" \
  "$ROOT/etc/anaconda/conf.d/90-mechos.conf"; do
  [[ ! -e "$legacy" ]] || fail "obsolete Fedora/KIWI file remains in the active tree: $legacy"
done

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
cp "$BASE/scripts/build-mechos-archiso.sh" "$tmpdir/builder.sh"
python3 "$BASE/scripts/patch-mechos-current.py" "$tmpdir/builder.sh" >/dev/null
bash -n "$tmpdir/builder.sh"
first_hash="$(sha256sum "$tmpdir/builder.sh" | awk '{print $1}')"
python3 "$BASE/scripts/patch-mechos-current.py" "$tmpdir/builder.sh" >/dev/null
second_hash="$(sha256sum "$tmpdir/builder.sh" | awk '{print $1}')"
[[ "$first_hash" == "$second_hash" ]] || fail "current integration patcher is not idempotent"
[[ "$(grep -c '^# MECHOS_CURRENT_INTEGRATION_EARLY$' "$tmpdir/builder.sh")" -eq 1 ]] || fail "early integration marker is duplicated"
[[ "$(grep -c '^# MECHOS_CURRENT_INTEGRATION_LATE$' "$tmpdir/builder.sh")" -eq 1 ]] || fail "late integration marker is duplicated"

wallpaper_dir="$ROOT/usr/share/backgrounds/mechos"
wallpaper_count="$(find "$wallpaper_dir" -maxdepth 1 -type f -name 'mechos-wallpaper-*.jpg' | wc -l)"
[[ "$wallpaper_count" -eq 19 ]] || fail "expected 19 wallpapers, got $wallpaper_count"
unique_count="$(sha256sum "$wallpaper_dir"/mechos-wallpaper-*.jpg | awk '{print $1}' | sort -u | wc -l)"
[[ "$unique_count" -eq 19 ]] || fail "expected 19 distinct wallpapers, got $unique_count"
for wallpaper in "$wallpaper_dir"/mechos-wallpaper-*.jpg; do
  file "$wallpaper" | grep -q '1920x1080' || fail "unexpected wallpaper dimensions: $wallpaper"
done

echo "MechOS 0.3.0 ArchISO static validation passed."
echo "Wallpapers: $wallpaper_count distinct 1920x1080 images."
