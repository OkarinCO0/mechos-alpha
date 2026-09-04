#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"
MANIFEST_SRC="/workspace/updates/stable.json"

log(){ printf '[MechOS Update Center v1] %s\n' "$*"; }
fail(){ printf '[MechOS Update Center v1] ERROR: %s\n' "$*" >&2; exit 1; }

[ -d "$ROOT" ] || fail "ArchISO rootfs missing"
[ -f "$MANIFEST_SRC" ] || fail "stable update manifest missing"

owner_file(){
  local tree="$1"
  local name="$2"
  local cls="$3"
  local public="$tree/usr/local/bin/$name"
  local libexec="$tree/usr/local/libexec/${name}-v5.py"
  if [ -f "$public" ] && grep -Fq "class $cls(" "$public"; then printf '%s\n' "$public"; return 0; fi
  if [ -f "$public.real" ] && grep -Fq "class $cls(" "$public.real"; then printf '%s\n' "$public.real"; return 0; fi
  if [ -f "$libexec" ] && grep -Fq "class $cls(" "$libexec"; then printf '%s\n' "$libexec"; return 0; fi
  return 1
}

install_helper(){
  local tree="$1"
  mkdir -p "$tree/usr/local/bin" "$tree/etc/mechos" "$tree/usr/share/mechos/update-channel"
  install -m 0644 "$MANIFEST_SRC" "$tree/usr/share/mechos/update-channel/stable.json"

  cat > "$tree/etc/mechos/update.conf" <<'EOF'
CHANNEL=stable
MANIFEST_URL=https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/stable.json
EOF
  chmod 0644 "$tree/etc/mechos/update.conf"

  cat > "$tree/usr/local/bin/mechos-update-helper" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

STATE_DIR="/var/lib/mechos"
CACHE_DIR="/var/cache/mechos/update-center"
LOG_DIR="/var/log/mechos"
HISTORY="$STATE_DIR/update-history.log"
LAST_RESULT="$STATE_DIR/last-update-result"
REBOOT_MARKER="$STATE_DIR/reboot-required"
SNAPSHOT_FILE="$STATE_DIR/last-preupdate-snapshot"
ROLLBACK_PENDING="$STATE_DIR/rollback-pending"
CURRENT_VERSION_FILE="/etc/mechos/release"
CONFIG_FILE="/etc/mechos/update.conf"
LOCAL_MANIFEST="/usr/share/mechos/update-channel/stable.json"
CACHED_MANIFEST="$CACHE_DIR/stable.json"
CHANNEL="stable"
MANIFEST_URL="https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/stable.json"

mkdir -p "$STATE_DIR" "$CACHE_DIR" "$LOG_DIR" 2>/dev/null || true

if [ -r "$CONFIG_FILE" ]; then
  cfg_channel="$(awk -F= '$1=="CHANNEL"{print substr($0,index($0,"=")+1); exit}' "$CONFIG_FILE" 2>/dev/null || true)"
  cfg_url="$(awk -F= '$1=="MANIFEST_URL"{print substr($0,index($0,"=")+1); exit}' "$CONFIG_FILE" 2>/dev/null || true)"
  [ -n "$cfg_channel" ] && CHANNEL="$cfg_channel"
  [ -n "$cfg_url" ] && MANIFEST_URL="$cfg_url"
fi

is_live(){
  [ -e /run/archiso/bootmnt ] || grep -q 'archiso' /proc/cmdline 2>/dev/null
}

require_installed(){
  if is_live; then
    echo "ERROR: Updates are disabled in the MechOS live ISO."
    exit 2
  fi
}

current_version(){
  if [ -r "$CURRENT_VERSION_FILE" ]; then
    head -n1 "$CURRENT_VERSION_FILE" | tr -d '[:space:]'
  else
    printf '0.0.0-unknown\n'
  fi
}

validate_manifest(){
  python3 - "$1" "$CHANNEL" <<'PY'
import json,re,sys
from urllib.parse import urlparse
p,channel=sys.argv[1],sys.argv[2]
with open(p,encoding='utf-8') as f: data=json.load(f)
if data.get('schema') != 1: raise SystemExit('unsupported manifest schema')
if data.get('channel') != channel: raise SystemExit('manifest channel mismatch')
version=str(data.get('version','')).strip()
if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){2}(?:[-.][A-Za-z0-9]+)*',version):
    raise SystemExit('invalid manifest version')
url=str(data.get('bundle_url','')).strip()
sha=str(data.get('bundle_sha256','')).strip().lower()
if bool(url) != bool(sha): raise SystemExit('bundle URL/SHA must be published together')
if url:
    u=urlparse(url)
    if u.scheme != 'https' or not u.netloc: raise SystemExit('bundle URL must use HTTPS')
    if not re.fullmatch(r'[0-9a-f]{64}',sha): raise SystemExit('invalid bundle SHA256')
if not isinstance(data.get('requires_reboot',False),bool): raise SystemExit('requires_reboot must be boolean')
PY
}

manifest_field(){
  python3 - "$1" "$2" <<'PY'
import json,sys
with open(sys.argv[1],encoding='utf-8') as f: data=json.load(f)
v=data.get(sys.argv[2],'')
if isinstance(v,bool): print('1' if v else '0')
elif isinstance(v,(dict,list)): print(json.dumps(v,separators=(',',':')))
else: print(str(v).replace('\n',' ').replace('\r',' '))
PY
}

fetch_manifest(){
  local tmp
  tmp="$(mktemp "$CACHE_DIR/manifest.XXXXXX")"
  if command -v curl >/dev/null 2>&1 && \
     curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
       --connect-timeout 8 --max-time 20 "$MANIFEST_URL" -o "$tmp"; then
    if validate_manifest "$tmp"; then
      mv -f "$tmp" "$CACHED_MANIFEST"
      chmod 0644 "$CACHED_MANIFEST" 2>/dev/null || true
      return 0
    fi
    echo "WARN: downloaded MechOS update manifest failed validation."
  else
    echo "WARN: unable to reach MechOS stable update manifest."
  fi
  rm -f "$tmp"

  if [ -s "$CACHED_MANIFEST" ] && validate_manifest "$CACHED_MANIFEST" 2>/dev/null; then
    echo "WARN: using cached MechOS update metadata."
    return 0
  fi
  if [ -s "$LOCAL_MANIFEST" ] && validate_manifest "$LOCAL_MANIFEST" 2>/dev/null; then
    cp -f "$LOCAL_MANIFEST" "$CACHED_MANIFEST"
    chmod 0644 "$CACHED_MANIFEST" 2>/dev/null || true
    echo "WARN: using bundled MechOS update metadata."
    return 0
  fi
  return 1
}

version_is_newer(){
  local current="$1" latest="$2" top
  [ "$current" != "$latest" ] || return 1
  top="$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -n1)"
  [ "$top" = "$latest" ]
}

mechos_state(){
  local current latest notes url sha reboot available=0
  current="$(current_version)"
  latest="$current"; notes=""; url=""; sha=""; reboot=0
  if fetch_manifest; then
    latest="$(manifest_field "$CACHED_MANIFEST" version)"
    notes="$(manifest_field "$CACHED_MANIFEST" notes)"
    url="$(manifest_field "$CACHED_MANIFEST" bundle_url)"
    sha="$(manifest_field "$CACHED_MANIFEST" bundle_sha256)"
    reboot="$(manifest_field "$CACHED_MANIFEST" requires_reboot)"
    if version_is_newer "$current" "$latest"; then available=1; fi
  fi
  printf 'CURRENT_MECHOS_VERSION=%s\n' "$current"
  printf 'LATEST_MECHOS_VERSION=%s\n' "$latest"
  printf 'MECHOS_UPDATE_AVAILABLE=%s\n' "$available"
  printf 'MECHOS_RELEASE_NOTES=%s\n' "$notes"
  printf 'MECHOS_BUNDLE_URL=%s\n' "$url"
  printf 'MECHOS_BUNDLE_SHA256=%s\n' "$sha"
  printf 'MECHOS_REQUIRES_REBOOT=%s\n' "$reboot"
}

check_updates(){
  require_installed
  echo "MECHOS_UPDATE_CHECK_BEGIN"

  local pacman_count=0 flatpak_count=0 mechos_count=0 updates="" state=""
  state="$(mechos_state)"
  printf '%s\n' "$state"
  mechos_count="$(printf '%s\n' "$state" | awk -F= '$1=="MECHOS_UPDATE_AVAILABLE"{print $2; exit}')"
  mechos_count="${mechos_count:-0}"

  if command -v checkupdates >/dev/null 2>&1; then
    updates="$(checkupdates 2>/dev/null || true)"
    if [ -n "$updates" ]; then
      echo "PACMAN_UPDATES_BEGIN"
      printf '%s\n' "$updates"
      echo "PACMAN_UPDATES_END"
      pacman_count="$(printf '%s\n' "$updates" | sed '/^[[:space:]]*$/d' | wc -l)"
    fi
  else
    echo "WARN: checkupdates is unavailable."
  fi

  if command -v flatpak >/dev/null 2>&1; then
    local flatpak_updates=""
    flatpak_updates="$(
      {
        flatpak remote-ls --system --updates --columns=application 2>/dev/null || true
        flatpak remote-ls --user --updates --columns=application 2>/dev/null || true
      } | sed '/^[[:space:]]*$/d' | sort -u
    )"
    if [ -n "$flatpak_updates" ]; then
      echo "FLATPAK_UPDATES_BEGIN"
      printf '%s\n' "$flatpak_updates"
      echo "FLATPAK_UPDATES_END"
      flatpak_count="$(printf '%s\n' "$flatpak_updates" | wc -l)"
    fi
  fi

  echo "MECHOS_COUNT=$mechos_count"
  echo "PACMAN_COUNT=$pacman_count"
  echo "FLATPAK_COUNT=$flatpak_count"
  echo "TOTAL_COUNT=$((mechos_count + pacman_count + flatpak_count))"
  echo "MECHOS_UPDATE_CHECK_END"
}

create_snapshot_if_possible(){
  rm -f "$SNAPSHOT_FILE"
  if ! command -v snapper >/dev/null 2>&1; then
    echo "[snapshot] snapper is not installed; skipping snapshot."
    return 0
  fi
  if ! snapper -c root list >/dev/null 2>&1; then
    echo "[snapshot] No configured root Snapper profile; skipping snapshot."
    return 0
  fi

  echo "[snapshot] Creating pre-update snapshot..."
  local snap_id=""
  snap_id="$(snapper -c root create --type single --description "MechOS pre-update $(date -Is)" --cleanup-algorithm number --print-number 2>/dev/null)" || {
    echo "[snapshot] Snapshot creation failed; continuing without it."
    return 0
  }
  if [[ "$snap_id" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$snap_id" > "$SNAPSHOT_FILE"
    chmod 0644 "$SNAPSHOT_FILE" 2>/dev/null || true
    echo "[snapshot] Pre-update snapshot $snap_id created."
  fi
}

mark_failure(){
  local reason="$1" log="$2"
  echo "FAILED $(date -Is) $reason" > "$LAST_RESULT"
  if [ -s "$SNAPSHOT_FILE" ]; then
    cp -f "$SNAPSHOT_FILE" "$ROLLBACK_PENDING"
    chmod 0644 "$ROLLBACK_PENDING" 2>/dev/null || true
    echo "[recovery] Failed update marked for rollback protection."
  fi
  printf '%s | FAILED | %s | %s\n' "$(date -Is)" "$reason" "$log" >> "$HISTORY"
}

validate_bundle_archive(){
  python3 - "$1" <<'PY'
from pathlib import PurePosixPath
import subprocess,sys
bundle=sys.argv[1]
p=subprocess.run(['tar','--zstd','-tf',bundle],text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
if p.returncode: raise SystemExit('unable to list update bundle')
allowed=(
 'usr/local/', 'usr/share/mechos/', 'usr/share/applications/',
 'usr/share/wayland-sessions/', 'usr/lib/systemd/', 'etc/mechos/',
 'etc/systemd/', 'etc/xdg/'
)
count=0
for raw in p.stdout.splitlines():
    name=raw.strip()
    while name.startswith('./'): name=name[2:]
    if not name or name=='.': continue
    path=PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts:
        raise SystemExit(f'unsafe bundle path: {name}')
    if not any(name==x.rstrip('/') or name.startswith(x) for x in allowed):
        raise SystemExit(f'path outside MechOS update allowlist: {name}')
    count += 1
if count == 0: raise SystemExit('empty MechOS update bundle')
PY
}

apply_mechos_bundle(){
  local state current latest available url sha reboot bundle stage expected actual release_name
  state="$(mechos_state)"
  current="$(printf '%s\n' "$state" | awk -F= '$1=="CURRENT_MECHOS_VERSION"{print substr($0,index($0,"=")+1); exit}')"
  latest="$(printf '%s\n' "$state" | awk -F= '$1=="LATEST_MECHOS_VERSION"{print substr($0,index($0,"=")+1); exit}')"
  available="$(printf '%s\n' "$state" | awk -F= '$1=="MECHOS_UPDATE_AVAILABLE"{print $2; exit}')"
  url="$(printf '%s\n' "$state" | awk -F= '$1=="MECHOS_BUNDLE_URL"{print substr($0,index($0,"=")+1); exit}')"
  sha="$(printf '%s\n' "$state" | awk -F= '$1=="MECHOS_BUNDLE_SHA256"{print substr($0,index($0,"=")+1); exit}')"
  reboot="$(printf '%s\n' "$state" | awk -F= '$1=="MECHOS_REQUIRES_REBOOT"{print $2; exit}')"

  [ "${available:-0}" = "1" ] || { echo "[mechos] MechOS-owned files are current ($current)."; return 0; }
  [ -n "$url" ] && [ -n "$sha" ] || { echo "ERROR: MechOS $latest is announced but its signed-hash bundle is not published."; return 20; }
  [[ "$url" == https://* ]] || { echo "ERROR: Refusing non-HTTPS MechOS update bundle."; return 21; }
  [[ "$sha" =~ ^[0-9a-fA-F]{64}$ ]] || { echo "ERROR: Invalid MechOS update bundle SHA256."; return 22; }

  bundle="$CACHE_DIR/mechos-$latest.tar.zst"
  echo "[mechos] Downloading MechOS $latest update bundle..."
  curl --fail --show-error --location --proto '=https' --tlsv1.2 --connect-timeout 10 --max-time 900 "$url" -o "$bundle.part" || return 23
  mv -f "$bundle.part" "$bundle"
  expected="$(printf '%s' "$sha" | tr 'A-F' 'a-f')"
  actual="$(sha256sum "$bundle" | awk '{print $1}')"
  [ "$actual" = "$expected" ] || { echo "ERROR: MechOS update bundle checksum mismatch."; rm -f "$bundle"; return 24; }

  validate_bundle_archive "$bundle" || { echo "ERROR: MechOS update bundle path validation failed."; return 25; }
  stage="$(mktemp -d "$CACHE_DIR/stage.XXXXXX")"
  if ! tar --zstd -xpf "$bundle" -C "$stage" --no-same-owner; then rm -rf "$stage"; return 26; fi
  echo "[mechos] Installing verified MechOS-owned files..."
  if ! rsync -aHAX --safe-links "$stage/" /; then rm -rf "$stage"; return 27; fi
  rm -rf "$stage"

  mkdir -p /etc/mechos
  printf '%s\n' "$latest" > /etc/mechos/release
  if [ -f /etc/mechos/mechos.conf ]; then
    if grep -q '^MECHOS_VERSION=' /etc/mechos/mechos.conf; then
      sed -i "s/^MECHOS_VERSION=.*/MECHOS_VERSION=$latest/" /etc/mechos/mechos.conf
    else
      printf 'MECHOS_VERSION=%s\n' "$latest" >> /etc/mechos/mechos.conf
    fi
  fi
  release_name="$(manifest_field "$CACHED_MANIFEST" release_name)"
  printf '%s\n' "${release_name:-MechOS $latest}" > /etc/system-release
  printf '%s\n' "$latest" > "$STATE_DIR/last-mechos-update-version"
  chmod 0644 /etc/mechos/release /etc/system-release "$STATE_DIR/last-mechos-update-version" 2>/dev/null || true
  systemctl daemon-reload 2>/dev/null || true
  [ "${reboot:-0}" = "1" ] && touch "$REBOOT_MARKER"
  echo "[mechos] MechOS updated from $current to $latest."
}

update_flatpaks(){
  command -v flatpak >/dev/null 2>&1 || return 0
  echo "[flatpak] Updating system Flatpaks..."
  flatpak update --system -y || echo "WARN: system Flatpak update reported a failure."

  if [[ "${PKEXEC_UID:-}" =~ ^[0-9]+$ ]]; then
    local user
    user="$(getent passwd "$PKEXEC_UID" | cut -d: -f1 || true)"
    if [ -n "$user" ] && [ "$user" != root ]; then
      echo "[flatpak] Updating user Flatpaks for $user..."
      runuser -u "$user" -- flatpak update --user -y || echo "WARN: user Flatpak update reported a failure."
    fi
  fi
}

apply_updates(){
  require_installed
  [ "$(id -u)" -eq 0 ] || { echo "ERROR: apply requires administrator privileges."; exit 1; }

  local stamp log pending packages_needing_reboot=0 rc=0
  stamp="$(date +'%Y%m%d-%H%M%S')"
  log="$LOG_DIR/update-$stamp.log"
  touch "$log"; chmod 0644 "$log"
  exec > >(tee -a "$log") 2>&1

  echo "MECHOS_UPDATE_APPLY_BEGIN"
  echo "Started: $(date -Is)"
  pending="$(checkupdates 2>/dev/null || true)"
  if printf '%s\n' "$pending" | awk '{print $1}' | grep -Eq '^(linux|linux-lts|linux-zen|linux-hardened|systemd|nvidia-open|nvidia-utils|mesa)$'; then
    packages_needing_reboot=1
  fi

  create_snapshot_if_possible

  echo "[pacman] Updating Arch system packages..."
  if ! pacman -Syu --needed --noconfirm; then
    rc=$?; mark_failure "pacman rc=$rc" "$log"; echo "MECHOS_UPDATE_APPLY_FAILED"; exit "$rc"
  fi
  echo "[pacman] System package update complete."

  update_flatpaks

  if ! apply_mechos_bundle; then
    rc=$?; mark_failure "MechOS bundle rc=$rc" "$log"; echo "MECHOS_UPDATE_APPLY_FAILED"; exit "$rc"
  fi

  if [ "$packages_needing_reboot" -eq 1 ] || [ ! -d "/usr/lib/modules/$(uname -r)" ]; then
    touch "$REBOOT_MARKER"
  fi

  rm -f "$ROLLBACK_PENDING"
  echo "SUCCESS $(date -Is)" > "$LAST_RESULT"
  printf '%s | SUCCESS | %s\n' "$(date -Is)" "$log" >> "$HISTORY"
  tail -n 100 "$HISTORY" > "$HISTORY.tmp" || true
  mv -f "$HISTORY.tmp" "$HISTORY" 2>/dev/null || true
  chmod 0644 "$HISTORY" "$LAST_RESULT" 2>/dev/null || true
  echo "REBOOT_REQUIRED=$([ -e "$REBOOT_MARKER" ] && echo 1 || echo 0)"
  echo "Finished: $(date -Is)"
  echo "MECHOS_UPDATE_APPLY_END"
}

show_status(){
  require_installed
  local current latest
  current="$(current_version)"; latest="$current"
  if [ -s "$CACHED_MANIFEST" ] && validate_manifest "$CACHED_MANIFEST" 2>/dev/null; then latest="$(manifest_field "$CACHED_MANIFEST" version)"; fi
  echo "CHANNEL=$CHANNEL"
  echo "CURRENT_MECHOS_VERSION=$current"
  echo "LATEST_MECHOS_VERSION=$latest"
  echo "REBOOT_REQUIRED=$([ -e "$REBOOT_MARKER" ] && echo 1 || echo 0)"
  echo "LAST_RESULT=$(cat "$LAST_RESULT" 2>/dev/null || echo 'No completed update yet')"
  echo "LAST_SNAPSHOT=$(cat "$SNAPSHOT_FILE" 2>/dev/null || true)"
  echo "ROLLBACK_PENDING=$([ -s "$ROLLBACK_PENDING" ] && echo 1 || echo 0)"
  echo "HISTORY_FILE=$HISTORY"
}

case "${1:-}" in
  check) check_updates ;;
  apply) apply_updates ;;
  status) show_status ;;
  history) cat "$HISTORY" 2>/dev/null || true ;;
  *) echo "Usage: mechos-update-helper {check|apply|status|history}" >&2; exit 2 ;;
esac
EOF
  chmod 0755 "$tree/usr/local/bin/mechos-update-helper"
  bash -n "$tree/usr/local/bin/mechos-update-helper" || fail "Update helper syntax failed in $tree"
}

patch_backend(){
  local tree="$1" owner
  owner="$(owner_file "$tree" mechos-update-center UpdateCenter)" || fail "Update Center owner missing in $tree"
  python3 - "$owner" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
t=p.read_text(encoding='utf-8')
marker='# MECHOS_UPDATE_CENTER_V1_BACKEND'
if marker in t:
    raise SystemExit(0)
anchor='\ndef main():'
pos=t.find(anchor)
if pos < 0: raise SystemExit('[Update Center v1] main anchor missing')
block=r'''
# MECHOS_UPDATE_CENTER_V1_BACKEND
_mechos_v1_original_finished = UpdateCenter.finished
_mechos_v1_original_load_status = UpdateCenter.load_status

def _mechos_v1_parse(output):
    values={}
    for line in output.splitlines():
        if '=' in line:
            key,value=line.split('=',1)
            if key in {'CURRENT_MECHOS_VERSION','LATEST_MECHOS_VERSION','MECHOS_UPDATE_AVAILABLE','MECHOS_RELEASE_NOTES','CHANNEL','REBOOT_REQUIRED','ROLLBACK_PENDING'}:
                values[key]=value
    return values

def _mechos_v1_set_version(self, current, latest):
    label=getattr(self,'version_label',None)
    if label is not None:
        label.setText(f'CURRENT  {current}    •    LATEST  {latest}')

def _mechos_v1_finished(self, mode, code):
    snapshot=self.check_buffer if mode=='check' else ''
    values=_mechos_v1_parse(snapshot)
    _mechos_v1_original_finished(self,mode,code)
    if mode=='check' and code==0:
        current=values.get('CURRENT_MECHOS_VERSION','unknown')
        latest=values.get('LATEST_MECHOS_VERSION',current)
        _mechos_v1_set_version(self,current,latest)
        if values.get('MECHOS_UPDATE_AVAILABLE')=='1':
            self.details_label.setText(f'MechOS {latest} is available. Arch and Flatpak updates are included in this scan.')
            notes=values.get('MECHOS_RELEASE_NOTES','').strip()
            if notes:
                self.log.appendPlainText('\nMECHOS RELEASE NOTES\n'+notes)

UpdateCenter.finished=_mechos_v1_finished

def _mechos_v1_load_status(self):
    _mechos_v1_original_load_status(self)
    try:
        out=subprocess.check_output([HELPER,'status'],text=True,stderr=subprocess.STDOUT)
    except Exception:
        return
    values=_mechos_v1_parse(out)
    current=values.get('CURRENT_MECHOS_VERSION','unknown')
    latest=values.get('LATEST_MECHOS_VERSION',current)
    _mechos_v1_set_version(self,current,latest)
    if values.get('ROLLBACK_PENDING')=='1':
        self.reboot_label.setText('Recovery available')

UpdateCenter.load_status=_mechos_v1_load_status
'''
t=t[:pos]+block+t[pos:]
compile(t,str(p),'exec')
p.write_text(t,encoding='utf-8')
PY
  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$owner" || fail "Update Center backend validation failed in $tree"
  grep -Fq 'MECHOS_UPDATE_CENTER_V1_BACKEND' "$owner" || fail "Update Center v1 backend marker missing in $tree"
}

patch_tree(){
  local tree="$1"
  install_helper "$tree"
  patch_backend "$tree"
}

patch_tree "$ROOT"

if [ -s "$ARCHIVE" ]; then
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  tar --zstd -xpf "$ARCHIVE" -C "$tmp"
  patch_tree "$tmp"
  replacement="$ARCHIVE.update-center-v1"
  tar --zstd -cpf "$replacement" -C "$tmp" .
  mv -f "$replacement" "$ARCHIVE"
  rm -rf "$tmp"; trap - EXIT
fi

log 'Stable manifest channel, version discovery, verified MechOS bundles, snapshots, rollback markers, Arch/Flatpak updates and reboot state are installed'
