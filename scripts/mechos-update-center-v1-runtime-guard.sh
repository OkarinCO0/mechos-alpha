#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"

log(){ printf '[MechOS Update Center v1 Guard] %s\n' "$*"; }
fail(){ printf '[MechOS Update Center v1 Guard] ERROR: %s\n' "$*" >&2; exit 1; }

patch_helper(){
  local tree="$1"
  local helper="$tree/usr/local/bin/mechos-update-helper"
  [ -f "$helper" ] || fail "Update helper missing in $tree"

  python3 - "$helper" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
t=p.read_text(encoding='utf-8')

# Update checks run as the signed-in desktop user, while apply runs as root.
# Never require an unprivileged check to write /var/cache; use a per-user cache
# for discovery and keep /var/cache for the privileged apply path.
cache_marker='# MECHOS_UPDATE_CENTER_USER_CACHE_V1'
if cache_marker not in t:
    old='CACHE_DIR="/var/cache/mechos/update-center"\n'
    new='''# MECHOS_UPDATE_CENTER_USER_CACHE_V1\nif [ "$(id -u)" -eq 0 ]; then\n  CACHE_DIR="/var/cache/mechos/update-center"\nelse\n  CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/mechos/update-center"\nfi\n'''
    if old not in t:
        raise SystemExit('[Update Center v1 Guard] cache directory anchor missing')
    t=t.replace(old,new,1)

marker='# MECHOS_UPDATE_CENTER_V1_RC_GUARD'
if marker not in t:
    old='''  echo "[pacman] Updating Arch system packages..."\n  if ! pacman -Syu --needed --noconfirm; then\n    rc=$?; mark_failure "pacman rc=$rc" "$log"; echo "MECHOS_UPDATE_APPLY_FAILED"; exit "$rc"\n  fi\n  echo "[pacman] System package update complete."\n\n  update_flatpaks\n\n  if ! apply_mechos_bundle; then\n    rc=$?; mark_failure "MechOS bundle rc=$rc" "$log"; echo "MECHOS_UPDATE_APPLY_FAILED"; exit "$rc"\n  fi\n'''
    new='''  # MECHOS_UPDATE_CENTER_V1_RC_GUARD\n  echo "[pacman] Updating Arch system packages..."\n  set +e\n  pacman -Syu --needed --noconfirm\n  rc=$?\n  set -e\n  if [ "$rc" -ne 0 ]; then\n    mark_failure "pacman rc=$rc" "$log"\n    echo "MECHOS_UPDATE_APPLY_FAILED"\n    exit "$rc"\n  fi\n  echo "[pacman] System package update complete."\n\n  update_flatpaks\n\n  set +e\n  apply_mechos_bundle\n  rc=$?\n  set -e\n  if [ "$rc" -ne 0 ]; then\n    mark_failure "MechOS bundle rc=$rc" "$log"\n    echo "MECHOS_UPDATE_APPLY_FAILED"\n    exit "$rc"\n  fi\n'''
    if old not in t:
        raise SystemExit('[Update Center v1 Guard] apply failure-handling anchor missing')
    t=t.replace(old,new,1)

# Keep the runtime dependency set minimal. coreutils is guaranteed on MechOS;
# rsync is not part of the installed package contract.
old_copy='''  if ! rsync -aHAX --safe-links "$stage/" /; then rm -rf "$stage"; return 27; fi\n'''
new_copy='''  if ! cp -a "$stage/." /; then rm -rf "$stage"; return 27; fi\n'''
if old_copy in t:
    t=t.replace(old_copy,new_copy,1)
elif 'cp -a "$stage/." /' not in t:
    raise SystemExit('[Update Center v1 Guard] bundle copy anchor missing')

p.write_text(t,encoding='utf-8')
PY

  chmod 0755 "$helper"
  bash -n "$helper" || fail "Update helper syntax failed after guard in $tree"
  grep -Fq 'MECHOS_UPDATE_CENTER_USER_CACHE_V1' "$helper" || fail "user cache marker missing in $tree"
  grep -Fq 'XDG_CACHE_HOME' "$helper" || fail "user cache path missing in $tree"
  grep -Fq 'MECHOS_UPDATE_CENTER_V1_RC_GUARD' "$helper" || fail "RC guard marker missing in $tree"
  grep -Fq 'cp -a "$stage/." /' "$helper" || fail "coreutils bundle copy path missing in $tree"
  ! grep -Fq 'if ! pacman -Syu' "$helper" || fail "unsafe negated pacman status capture remains in $tree"
  ! grep -Fq 'if ! apply_mechos_bundle' "$helper" || fail "unsafe negated bundle status capture remains in $tree"
}

patch_helper "$ROOT"

if [ -s "$ARCHIVE" ]; then
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  tar --zstd -xpf "$ARCHIVE" -C "$tmp"
  patch_helper "$tmp"
  replacement="$ARCHIVE.update-center-v1-guard"
  tar --zstd -cpf "$replacement" -C "$tmp" .
  mv -f "$replacement" "$ARCHIVE"
  rm -rf "$tmp"; trap - EXIT
fi

log 'Update checks use a writable per-user manifest cache; apply keeps the privileged system cache; failures preserve real exit codes and verified bundles install without rsync'
