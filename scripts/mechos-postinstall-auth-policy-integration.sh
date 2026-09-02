#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
PAYLOAD="$ROOT/usr/share/mechos/install-payload"
ARCHIVE="$PAYLOAD/mechos-rootfs.tar.zst"

log() { printf '[MechOS Auth Policy] %s\n' "$*"; }
fail() { printf '[MechOS Auth Policy] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Auth Policy] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"
[ -s "$ARCHIVE" ] || fail "installed-system payload archive is missing: $ARCHIVE"

patch_installed_tree() {
  local tree="$1"
  local oobe_apply="$tree/usr/local/libexec/mechos-oobe-apply"
  local oobe_ui="$tree/usr/local/bin/mechos-oobe"
  local lock_cfg="$tree/etc/xdg/kscreenlockerrc"
  local selector="$tree/usr/local/bin/mechos-session-select"
  local return_cmd="$tree/usr/local/bin/mechos-return-to-mechscope"

  [ -f "$oobe_apply" ] || fail "OOBE apply helper is missing: $oobe_apply"
  [ -f "$selector" ] || fail "installed mode switcher is missing: $selector"
  [ -f "$return_cmd" ] || fail "Return to MechScope helper is missing: $return_cmd"

  python3 - "$oobe_apply" "$oobe_ui" <<'PY'
from pathlib import Path
import sys

apply_path = Path(sys.argv[1])
ui_path = Path(sys.argv[2])

text = apply_path.read_text(encoding="utf-8")
old = '    f"User={username}\\n"\n'
new = '    "User=\\n"\n'
if old not in text and '    "User=\\n"\n' not in text:
    raise SystemExit(f"could not locate post-OOBE SDDM autologin user in {apply_path}")
text = text.replace(old, new)
apply_path.write_text(text, encoding="utf-8")

if ui_path.is_file():
    ui = ui_path.read_text(encoding="utf-8")
    ui = ui.replace(
        "After setup MechOS will reboot once, show the navigation tutorial, then enter MechScope.",
        "After setup MechOS will reboot once. Sign in with the password you created, then MechOS will show the navigation tutorial and enter MechScope.",
    )
    ui = ui.replace(
        "Finishing setup will configure the account, switch the next login to MechScope, and reboot the system.",
        "Finishing setup will configure the account and reboot to the MechOS sign-in screen.",
    )
    ui = ui.replace(
        "Setup is complete. MechOS will reboot into your account and show the navigation tutorial before MechScope.",
        "Setup is complete. MechOS will reboot to the sign-in screen. Enter your password once, then the navigation tutorial and MechScope will start.",
    )
    ui_path.write_text(ui, encoding="utf-8")
PY

  mkdir -p "$(dirname "$lock_cfg")"
  cat > "$lock_cfg" <<'LOCK_EOF'
[Daemon]
# Do not interrupt an authenticated gaming/creator/desktop session just because
# it has been idle. Resume from suspend must still require authentication.
Autolock=false
LockOnResume=true
Timeout=0
LOCK_EOF

  # Mode switching must stay inside the already-authenticated Plasma session.
  for file in "$selector" "$return_cmd"; do
    if grep -Eq '(^|[[:space:]])(sudo|pkexec|loginctl)([[:space:]]|$)' "$file"; then
      fail "authentication/session-termination command found in mode-switch path: $file"
    fi
  done

  grep -Fq '"User=\\n"' "$oobe_apply" \
    || fail "post-OOBE SDDM autologin was not disabled"
  grep -Fq 'Autolock=false' "$lock_cfg" \
    || fail "installed idle-lock policy is missing"
  grep -Fq 'LockOnResume=true' "$lock_cfg" \
    || fail "installed resume-lock policy is missing"

  python3 -m py_compile "$oobe_apply"
  [ ! -f "$oobe_ui" ] || python3 -m py_compile "$oobe_ui"
  bash -n "$selector"
  bash -n "$return_cmd"
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

tar --zstd -xf "$ARCHIVE" -C "$tmp"
patch_installed_tree "$tmp"

new_archive="$ARCHIVE.auth-policy"
tar --zstd -cf "$new_archive" -C "$tmp" .
mv -f "$new_archive" "$ARCHIVE"

rm -rf "$tmp"
trap - EXIT

log "Installed MechOS now requires login after boot and unlock after resume, with passwordless in-session mode switching"
