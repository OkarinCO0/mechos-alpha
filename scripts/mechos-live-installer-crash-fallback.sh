#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
BIN="$ROOT/usr/local/bin"
PROFILE="/workspace/archlive/profiledef.sh"
PUBLIC="$BIN/mechos-live-setup"
REAL="$ROOT/usr/local/libexec/mechos-live-setup-v5.py"
SAFE="$BIN/mechos-live-setup-safe"

log() { printf '[MechOS Live Installer Fallback] %s\n' "$*"; }
fail() { printf '[MechOS Live Installer Fallback] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Live Installer Fallback] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ -f "$PUBLIC" ] || fail "guarded Live installer is missing: $PUBLIC"
[ -f "$REAL" ] || fail "Reference v5 Python installer is missing: $REAL"

cat > "$SAFE" <<'SAFE_EOF'
#!/usr/bin/env bash
# MECHOS_LIVE_INSTALLER_SAFE_FALLBACK_V1
set -Eeuo pipefail

LOG=/tmp/mechos-live-setup.log
SELECTION=/tmp/mechos-install-target.json

notify_error() {
  local message="$1"
  if command -v kdialog >/dev/null 2>&1; then
    kdialog --title "MechOS Safe Installer" --error "$message" || true
  else
    printf 'MechOS Safe Installer: %s\n' "$message" >&2
  fi
}

command -v kdialog >/dev/null 2>&1 || {
  if command -v konsole >/dev/null 2>&1; then
    exec konsole -e bash -lc "echo 'The graphical Reference installer crashed.'; echo 'Crash log: $LOG'; echo; echo 'Use the MechOS terminal installer only after reviewing its disk summary.'; echo; read -rp 'Press Enter to open the terminal installer or Ctrl+C to cancel...'; sudo /usr/local/bin/mechos-install --terminal"
  fi
  printf 'Reference installer failed and kdialog/konsole are unavailable. See %s\n' "$LOG" >&2
  exit 1
}

mode="$(kdialog --title "MechOS Safe Installer" --menu \
  "The Reference UI exited unexpectedly. Choose a safe MechOS installer path, or Cancel to make no disk changes." \
  clean "Clean Install — select one whole drive, then use the MechOS native installer" \
  keep "Keep Personal Data — reinstall/update while preserving /home" \
  custom "Custom Install — explicit manual partitioning" \
  alongside "Install Alongside Existing OS — guided dual-boot assistant" \
  logs "Open installer crash log" \
  2>/dev/null || true)"

case "$mode" in
  clean)
    live_source="$(findmnt -n -o SOURCE /run/archiso/bootmnt 2>/dev/null || true)"
    live_disk=""
    if [[ "$live_source" == /dev/* ]]; then
      parent="$(lsblk -ndo PKNAME "$live_source" 2>/dev/null || true)"
      live_disk="${parent:+/dev/$parent}"
      [ -n "$live_disk" ] || live_disk="$live_source"
    fi

    items=()
    while IFS='|' read -r dev size model; do
      [ -n "$dev" ] || continue
      [ "$dev" != "$live_disk" ] || continue
      items+=("$dev" "${model:-Disk}  ${size}")
    done < <(
      lsblk -dpno NAME,SIZE,TYPE,MODEL 2>/dev/null | \
        awk '$3=="disk" {dev=$1; size=$2; $1=$2=$3=""; sub(/^[[:space:]]+/,""); print dev "|" size "|" $0}'
    )

    if [ "${#items[@]}" -eq 0 ]; then
      notify_error "No installable whole disks were detected. zram, loop devices, optical media, and the active Live media are not offered as Clean Install targets."
      exit 1
    fi

    target="$(kdialog --title "Select MechOS Target Drive" --menu \
      "Choose the whole drive for Clean Install. The selected drive can be erased after the final confirmation." \
      "${items[@]}" 2>/dev/null || true)"
    [ -n "$target" ] || exit 0

    [ "$(lsblk -dno TYPE "$target" 2>/dev/null || true)" = "disk" ] || {
      notify_error "The selected target is no longer a whole disk: $target"
      exit 1
    }

    size_bytes="$(lsblk -bdno SIZE "$target" 2>/dev/null | tr -d '[:space:]')"
    [[ "$size_bytes" =~ ^[0-9]+$ ]] || {
      notify_error "MechOS could not read the selected drive size. No changes were made."
      exit 1
    }

    python3 - "$SELECTION" "$target" "$size_bytes" <<'PY'
import json, sys
from pathlib import Path
path=Path(sys.argv[1])
target=sys.argv[2]
size=int(sys.argv[3])
path.write_text(json.dumps({
    'kind':'disk',
    'path':target,
    'disk':target,
    'size_bytes':size,
    'fstype':'',
    'label':'',
}, indent=2), encoding='utf-8')
PY

    if ! kdialog --title "Confirm Clean Install" --warningyesno \
      "Clean Install will erase and repartition:\n\n$target\n\nOnly continue if this is the drive you intend to replace. The MechOS native installer will show its own final confirmation before destructive work."; then
      exit 0
    fi

    exec /usr/local/bin/mechos-native-install
    ;;

  keep)
    exec konsole -e sudo /usr/local/bin/mechos-live-update-keep-home
    ;;

  custom)
    exec konsole -e sudo /usr/local/bin/mechos-install --terminal --preserve-home
    ;;

  alongside)
    exec konsole -e sudo /usr/local/bin/mechos-alongside-assistant
    ;;

  logs)
    if command -v kate >/dev/null 2>&1; then
      exec kate "$LOG"
    fi
    exec konsole -e bash -lc "cat '$LOG'; echo; read -rp 'Press Enter to close...'"
    ;;

  *)
    exit 0
    ;;
esac
SAFE_EOF
chmod 755 "$SAFE"

python3 - "$PUBLIC" <<'PY'
from pathlib import Path
import sys

path=Path(sys.argv[1])
text=path.read_text(encoding='utf-8')
marker='# MECHOS_LIVE_INSTALLER_CRASH_FALLBACK_V1'
if marker in text:
    raise SystemExit(0)

old='''  export PYTHONFAULTHANDLER=1
  exec /usr/bin/python3 -X faulthandler "$REAL" "$@"
'''
new='''  # MECHOS_LIVE_INSTALLER_CRASH_FALLBACK_V1
  if [ "${1:-}" = "--safe" ]; then
    exec /usr/local/bin/mechos-live-setup-safe
  fi

  export PYTHONFAULTHANDLER=1
  set +e
  /usr/bin/python3 -X faulthandler "$REAL" "$@"
  rc=$?
  set -e

  if [ "$rc" -eq 0 ]; then
    exit 0
  fi

  printf 'Reference installer exited abnormally (rc=%s).\\n' "$rc"
  if command -v coredumpctl >/dev/null 2>&1; then
    printf '%s\\n' '--- Recent python coredump metadata ---'
    coredumpctl info /usr/bin/python3 --no-pager 2>/dev/null | tail -n 140 || true
  fi

  if command -v kdialog >/dev/null 2>&1; then
    if kdialog --title "MechOS Installer Recovery" --warningyesno \\
      "The Reference installer exited unexpectedly.\\n\\nCrash details were saved to /tmp/mechos-live-setup.log.\\n\\nOpen the safe MechOS installer now?"; then
      exec /usr/local/bin/mechos-live-setup-safe
    fi
  fi

  exit "$rc"
'''
if old not in text:
    raise SystemExit('[MechOS Live Installer Fallback] guarded Python launch block not found')
text=text.replace(old,new,1)
path.write_text(text,encoding='utf-8')
PY

bash -n "$PUBLIC" || fail "patched Live installer wrapper shell syntax failed"
bash -n "$SAFE" || fail "safe fallback shell syntax failed"
grep -Fq '# MECHOS_LIVE_INSTALLER_CRASH_FALLBACK_V1' "$PUBLIC" || fail "crash fallback marker missing from public launcher"
grep -Fq '# MECHOS_LIVE_INSTALLER_SAFE_FALLBACK_V1' "$SAFE" || fail "safe installer marker missing"
grep -Fq '/usr/local/bin/mechos-native-install' "$SAFE" || fail "safe Clean Install does not use the native installer"
grep -Fq 'mechos-live-update-keep-home' "$SAFE" || fail "safe Keep Home path is missing"
grep -Fq 'mechos-alongside-assistant' "$SAFE" || fail "safe Alongside path is missing"
grep -Fq -- '--preserve-home' "$SAFE" || fail "safe Custom path is missing"

if [ -f "$PROFILE" ] && ! grep -Fq 'file_permissions["/usr/local/bin/mechos-live-setup-safe"]' "$PROFILE"; then
  printf '\nfile_permissions["/usr/local/bin/mechos-live-setup-safe"]="0:0:755"\n' >> "$PROFILE"
fi

log "Reference installer now records abnormal exits and offers a confirmed safe fallback instead of leaving the Live system without an installer"
