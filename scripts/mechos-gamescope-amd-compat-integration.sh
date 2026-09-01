#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
PAYLOAD="$ROOT/usr/share/mechos/install-payload"
ARCHIVE="$PAYLOAD/mechos-rootfs.tar.zst"

log() { printf '[MechOS Gamescope Compat] %s\n' "$*"; }
fail() { printf '[MechOS Gamescope Compat] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Gamescope Compat] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"

patch_tree() {
  local tree="$1"
  local layer="$tree/usr/local/bin/mechos-gaming-layer"

  [ -f "$layer" ] || fail "gaming layer is missing: $layer"

  python3 - "$layer" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = "# MECHOS_GAMESCOPE_BACKEND_FALLBACK_V1"
if marker in text:
    raise SystemExit(0)

start = text.find("run_mechscope() {")
end = text.find("\n}\n\nset +e\nrun_mechscope", start)
if start < 0 or end < 0:
    raise SystemExit(f"could not locate run_mechscope() in {path}")
end += 2

replacement = r'''# MECHOS_GAMESCOPE_BACKEND_FALLBACK_V1
log_graphics_state() {
  {
    printf '[Graphics] Kernel: %s\n' "$(uname -r 2>/dev/null || true)"
    lspci -nnk 2>/dev/null | grep -A3 -Ei 'VGA|3D|Display' || true
    if command -v gamescope >/dev/null 2>&1; then
      gamescope --version 2>&1 || true
    fi
    if command -v vulkaninfo >/dev/null 2>&1; then
      timeout 4s vulkaninfo --summary 2>&1 | head -n 80 || true
    fi
  } >>"$LOG_FILE"
}

quick_exit_without_mode_request() {
  local started="$1"
  local ended elapsed
  ended="$(date +%s)"
  elapsed=$((ended - started))
  [ "$elapsed" -lt 8 ] && [ ! -s "$MODE_FILE" ]
}

run_gamescope_backend() {
  local backend="$1"
  local started rc=0
  started="$(date +%s)"

  printf '[MechOS] Gamescope attempt: backend=%s\n' "$backend" >>"$LOG_FILE"
  set +e
  if [ "$backend" = "wayland" ]; then
    gamescope -e -f --mangoapp -- /usr/local/bin/mechscope >>"$LOG_FILE" 2>&1
  else
    gamescope -e -f --backend "$backend" --mangoapp -- /usr/local/bin/mechscope >>"$LOG_FILE" 2>&1
  fi
  rc=$?
  set -e

  if [ "$rc" -eq 0 ] && quick_exit_without_mode_request "$started"; then
    printf '[MechOS] Gamescope backend=%s closed in under 8 seconds without a mode request; treating as startup failure.\n' "$backend" >>"$LOG_FILE"
    rc=75
  fi
  return "$rc"
}

run_direct_mechscope() {
  local started rc=0
  started="$(date +%s)"
  printf '[MechOS] Starting direct fullscreen MechScope fallback.\n' >>"$LOG_FILE"
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

  if command -v gamescope >/dev/null 2>&1 && [ "${MECHOS_DISABLE_GAMESCOPE:-0}" != "1" ]; then
    # Prefer Gamescope's normal nested Wayland backend first. Current upstream
    # Gamescope can still hit backend-specific failures on some AMD/KDE Wayland
    # combinations, so retry with SDL before abandoning Gamescope entirely.
    printf '[MechOS] Starting nested Gamescope + MechScope over Plasma.\n' >>"$LOG_FILE"
    if run_gamescope_backend wayland; then
      return 0
    fi
    rc=$?
    printf '[MechOS] Wayland Gamescope failed rc=%s; retrying with SDL backend.\n' "$rc" >>"$LOG_FILE"

    if run_gamescope_backend sdl; then
      return 0
    fi
    rc=$?
    printf '[MechOS] SDL Gamescope failed rc=%s; using direct MechScope fallback.\n' "$rc" >>"$LOG_FILE"
  fi

  run_direct_mechscope
}
'''

text = text[:start] + replacement + text[end:]
path.write_text(text, encoding="utf-8")
PY

  chmod 755 "$layer"
  bash -n "$layer" || fail "gaming-layer syntax failed after Gamescope compatibility patch"
  grep -Fq '# MECHOS_GAMESCOPE_BACKEND_FALLBACK_V1' "$layer" \
    || fail "Gamescope compatibility marker is missing"
  grep -Fq 'run_gamescope_backend sdl' "$layer" \
    || fail "SDL Gamescope fallback is missing"
  grep -Fq 'closed in under 8 seconds' "$layer" \
    || fail "quick-exit protection is missing"
}

patch_tree "$ROOT"

if [ -s "$ARCHIVE" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  tar --zstd -xf "$ARCHIVE" -C "$tmp"
  patch_tree "$tmp"
  new_archive="$ARCHIVE.gamescope-compat"
  tar --zstd -cf "$new_archive" -C "$tmp" .
  mv -f "$new_archive" "$ARCHIVE"
  rm -rf "$tmp"
  trap - EXIT
fi

log "Gamescope backend fallback and quick-exit recovery applied"
