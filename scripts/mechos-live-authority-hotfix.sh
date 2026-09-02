#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
BIN="$ROOT/usr/local/bin"
LIBEXEC="$ROOT/usr/local/libexec"
SDDM="$ROOT/etc/sddm.conf.d"
SYSTEMD="$ROOT/etc/systemd/system"
PROFILE="/workspace/archlive/profiledef.sh"

log() { printf '[MechOS Live Authority] %s\n' "$*"; }
fail() { printf '[MechOS Live Authority] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Live Authority] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"
[ -x "$BIN/mechos-live-setup" ] || fail "graphical Live installer is missing"
[ -x "$BIN/mechos-native-install" ] || fail "native MechOS installer is missing"
[ -x "$BIN/mechos-live-update-keep-home" ] || fail "Keep Home updater is missing"
mkdir -p "$BIN" "$LIBEXEC" "$SDDM" "$SYSTEMD/sddm.service.d"

# ---------------------------------------------------------------------------
# Live login authority
# ---------------------------------------------------------------------------
# SDDM is the only graphical-login authority in the Live image. The legacy
# tty1 autologin path can create a second login session and is unnecessary once
# SDDM autologin is reliable.
rm -f "$SYSTEMD/getty@tty1.service.d/autologin.conf"

cat > "$LIBEXEC/mechos-live-session-prepare" <<'PREP_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

# Never modify an installed system. This helper exists only to make the
# disposable ArchISO account deterministic before SDDM starts.
if ! { [ -e /run/archiso/bootmnt ] || grep -q 'archiso' /proc/cmdline 2>/dev/null; }; then
  exit 0
fi

if ! getent passwd mechos >/dev/null 2>&1; then
  useradd -m -u 1000 -s /bin/bash mechos
fi

usermod -s /bin/bash mechos

# Add only groups that exist in this image.
groups=()
for group in wheel video audio input storage optical; do
  getent group "$group" >/dev/null 2>&1 && groups+=("$group")
done
if [ "${#groups[@]}" -gt 0 ]; then
  joined="$(IFS=,; echo "${groups[*]}")"
  usermod -aG "$joined" mechos
fi

mkdir -p /home/mechos
if [ -d /etc/skel ]; then
  cp -an /etc/skel/. /home/mechos/ 2>/dev/null || true
fi
chown -R mechos:mechos /home/mechos
chmod 0755 /home/mechos

# systemd-sysusers creates accounts locked by default. The Live account is
# intentionally passwordless and disposable; installed users are unaffected.
passwd -d mechos >/dev/null 2>&1 || true

mkdir -p /run/mechos
printf 'ready\n' > /run/mechos/live-session-ready
PREP_EOF
chmod 755 "$LIBEXEC/mechos-live-session-prepare"

cat > "$SYSTEMD/mechos-live-session-prepare.service" <<'SERVICE_EOF'
[Unit]
Description=Prepare MechOS Live desktop account
After=systemd-sysusers.service systemd-tmpfiles-setup.service
Before=sddm.service display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-live-session-prepare
RemainAfterExit=yes
SERVICE_EOF

cat > "$SYSTEMD/sddm.service.d/10-mechos-live-prepare.conf" <<'DROPIN_EOF'
[Unit]
Wants=mechos-live-session-prepare.service
After=mechos-live-session-prepare.service
DROPIN_EOF

# One authoritative Live SDDM override. Relogin MUST remain false: if Plasma
# ever exits unexpectedly, SDDM stays at the greeter instead of creating an
# endless automatic login -> crash -> automatic login loop.
cat > "$SDDM/99-mechos-live.conf" <<'SDDM_EOF'
[Autologin]
User=mechos
Session=plasma
Relogin=false
SDDM_EOF

# Remove older competing Live autologin sections. Keep installed/OOBE configs
# in the payload untouched; this operates only on the Live rootfs.
for cfg in "$SDDM"/*.conf; do
  [ -f "$cfg" ] || continue
  [ "$(basename "$cfg")" = "99-mechos-live.conf" ] && continue
  if grep -Fq 'User=mechos' "$cfg" 2>/dev/null; then
    rm -f "$cfg"
  fi
done

# ---------------------------------------------------------------------------
# Native installer authority
# ---------------------------------------------------------------------------
# Keep /usr/local/bin/mechos-install as a compatibility command for old
# launchers, but make it impossible for that command to invoke Archinstall.
# If a disk has already been selected, continue directly into the native
# installer. Otherwise reopen the MechOS graphical selector.
cat > "$BIN/mechos-install" <<'INSTALL_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

case " $* " in
  *" --preserve-home "*)
    exec /usr/local/bin/mechos-live-update-keep-home
    ;;
esac

if [ -s /tmp/mechos-install-target.json ]; then
  exec /usr/local/bin/mechos-native-install
fi

exec /usr/local/bin/mechos-live-setup
INSTALL_EOF
chmod 755 "$BIN/mechos-install"

# The old preserve-home helper used to redirect the user to Archinstall manual
# partitioning. It is now just a compatibility alias for the real Keep Home
# updater and never opens Archinstall.
cat > "$BIN/mechos-preserve-home" <<'KEEP_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
exec /usr/local/bin/mechos-live-update-keep-home "$@"
KEEP_EOF
chmod 755 "$BIN/mechos-preserve-home"

# Remove stale Archinstall wording from the final graphical installer. Runtime
# routing is protected by mechos-install above even if UI text changes later.
python3 - "$BIN/mechos-live-setup" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
replacements = {
    "Archinstall will still display the final partition/disk summary and require confirmation before formatting.":
        "MechOS will format and install only to the selected target after final confirmation.",
    "Review Archinstall's final disk summary before confirming.":
        "Review the MechOS target summary before confirming.",
    "MechOS/Archinstall": "MechOS",
    "Archinstall": "MechOS installer",
}
for old, new in replacements.items():
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
PY

# ArchISO permissions for newly authoritative runtime files.
if [ -f "$PROFILE" ]; then
  for path in \
    /usr/local/bin/mechos-install \
    /usr/local/bin/mechos-preserve-home \
    /usr/local/libexec/mechos-live-session-prepare; do
    if ! grep -Fq "file_permissions[\"$path\"]" "$PROFILE"; then
      printf '\nfile_permissions["%s"]="0:0:755"\n' "$path" >> "$PROFILE"
    fi
  done
fi

# ---------------------------------------------------------------------------
# Build guards: these are deliberately strict because both regressions were
# caused by older generated code surviving later integration passes.
# ---------------------------------------------------------------------------
bash -n "$BIN/mechos-install" || fail "native compatibility installer syntax failed"
bash -n "$BIN/mechos-preserve-home" || fail "Keep Home compatibility helper syntax failed"
bash -n "$LIBEXEC/mechos-live-session-prepare" || fail "Live session prepare syntax failed"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$BIN/mechos-live-setup" \
  || fail "Live installer Python validation failed"

grep -Fq 'Session=plasma' "$SDDM/99-mechos-live.conf" || fail "Live Plasma session is not authoritative"
grep -Fq 'Relogin=false' "$SDDM/99-mechos-live.conf" || fail "Live SDDM can still auto-relogin"
if grep -Rqs 'Relogin=true' "$SDDM"; then
  fail "a competing Live SDDM config can still create a login loop"
fi
[ ! -e "$SYSTEMD/getty@tty1.service.d/autologin.conf" ] \
  || fail "legacy tty1 Live autologin still exists"

grep -Fq 'exec /usr/local/bin/mechos-native-install' "$BIN/mechos-install" \
  || fail "legacy installer command no longer routes selected disks to native installer"
grep -Fq 'exec /usr/local/bin/mechos-live-update-keep-home' "$BIN/mechos-preserve-home" \
  || fail "preserve-home compatibility path is not native"
if grep -Eqs '(^|[[:space:]])archinstall([[:space:]]|$)' "$BIN/mechos-install" "$BIN/mechos-preserve-home"; then
  fail "a user-facing Live installer compatibility command still invokes Archinstall"
fi

log "Live login is single-shot/stable and every compatibility installer path is MechOS-native"
