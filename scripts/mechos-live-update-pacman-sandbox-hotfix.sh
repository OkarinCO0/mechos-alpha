#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
FILE="$ROOT/usr/local/bin/mechos-live-update-keep-home"

log() { printf '[MechOS Live Update Pacman] %s\n' "$*"; }
fail() { printf '[MechOS Live Update Pacman] ERROR: %s\n' "$*" >&2; exit 1; }

[ -f "$FILE" ] || fail "Live Update helper is missing: $FILE"

python3 - "$FILE" <<'PY'
from pathlib import Path
import sys

path=Path(sys.argv[1])
text=path.read_text(encoding='utf-8')
marker='# MECHOS_LIVE_UPDATE_PACMAN_SANDBOX_V1'
if marker in text:
    raise SystemExit(0)

anchor='PKG_RESULT="offline/skipped"\n'
if anchor not in text:
    raise SystemExit('[MechOS Live Update Pacman] package-refresh anchor missing')

helper=r'''# MECHOS_LIVE_UPDATE_PACMAN_SANDBOX_V1
prepare_pacman_live_chroot() {
  local download_user=""

  # The ISO refresh intentionally preserves the installed account database.
  # A newer pacman can therefore arrive before newer package-owned system users
  # (notably the DownloadUser) exist in /etc/passwd. Re-run sysusers definitions
  # from the refreshed runtime without modifying existing human accounts.
  if [ -x "$MNT/usr/bin/systemd-sysusers" ]; then
    arch-chroot "$MNT" systemd-sysusers >/dev/null 2>&1 || \
      say "WARNING: system user refresh reported an error; continuing with validation."
  fi

  # Pacman 7+ downloads through a restricted user/sandbox. Keep the standard
  # system paths traversable and remove only stale pacman temporary downloads
  # left by an interrupted/older refresh. No package database is deleted.
  mkdir -p \
    "$MNT/var/lib/pacman/sync" \
    "$MNT/var/cache/pacman/pkg"
  chmod 755 \
    "$MNT/etc" \
    "$MNT/var" \
    "$MNT/var/lib" \
    "$MNT/var/lib/pacman" \
    "$MNT/var/lib/pacman/sync" \
    "$MNT/var/cache" \
    "$MNT/var/cache/pacman" \
    "$MNT/var/cache/pacman/pkg" 2>/dev/null || true
  find "$MNT/var/lib/pacman/sync" -maxdepth 1 -type d -name 'download-*' -exec rm -rf -- {} + 2>/dev/null || true
  find "$MNT/var/cache/pacman/pkg" -maxdepth 1 -type d -name 'download-*' -exec rm -rf -- {} + 2>/dev/null || true

  if [ -x "$MNT/usr/bin/pacman-conf" ]; then
    download_user="$(arch-chroot "$MNT" pacman-conf DownloadUser 2>/dev/null | awk 'NF {print $1; exit}' || true)"
  fi
  if [ -n "$download_user" ]; then
    if arch-chroot "$MNT" getent passwd "$download_user" >/dev/null 2>&1; then
      say "Pacman sandbox user ready: $download_user"
    else
      say "WARNING: Pacman DownloadUser '$download_user' is still unavailable after system-user refresh."
    fi
  fi
}

pacman_live_update() {
  prepare_pacman_live_chroot

  # Normal path first: preserve Pacman's standard DownloadUser and sandbox.
  if arch-chroot "$MNT" pacman -Syu --noconfirm; then
    return 0
  fi

  # A Live-image chroot can expose Landlock/account/permission mismatches that
  # do not exist after a normal boot. Pacman 7.1 provides --disable-sandbox for
  # this class of failure. Use it for this one retry only; never edit the target
  # pacman.conf, so the installed OS keeps normal sandboxing on subsequent runs.
  if arch-chroot "$MNT" pacman --help 2>&1 | grep -Fq -- '--disable-sandbox'; then
    say "Sandboxed package refresh failed; retrying once with the Live-chroot sandbox disabled."
    find "$MNT/var/lib/pacman/sync" -maxdepth 1 -type d -name 'download-*' -exec rm -rf -- {} + 2>/dev/null || true
    arch-chroot "$MNT" pacman --disable-sandbox -Syu --noconfirm
    return $?
  fi

  return 1
}

'''
text=text.replace(anchor,helper+anchor,1)
old='''  if arch-chroot "$MNT" pacman -Syu --noconfirm; then\n    PKG_RESULT="updated"\n'''
new='''  if pacman_live_update; then\n    PKG_RESULT="updated"\n'''
if old not in text:
    raise SystemExit('[MechOS Live Update Pacman] pacman refresh call not found')
text=text.replace(old,new,1)
path.write_text(text,encoding='utf-8')
PY

bash -n "$FILE" || fail "patched Live Update helper failed shell syntax"
grep -Fq 'MECHOS_LIVE_UPDATE_PACMAN_SANDBOX_V1' "$FILE" || fail "sandbox marker missing"
grep -Fq 'systemd-sysusers' "$FILE" || fail "system-user repair missing"
grep -Fq 'pacman-conf DownloadUser' "$FILE" || fail "DownloadUser validation missing"
grep -Fq "-name 'download-*'" "$FILE" || fail "stale download cleanup missing"
grep -Fq -- '--disable-sandbox' "$FILE" || fail "one-shot sandbox fallback missing"
grep -Fq 'if pacman_live_update; then' "$FILE" || fail "package refresh does not use hardened path"

log "Live Update pacman refresh now repairs sandbox prerequisites and has a one-shot chroot fallback"
