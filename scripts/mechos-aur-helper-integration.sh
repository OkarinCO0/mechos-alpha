#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"

log() { printf '[MechOS AUR] %s\n' "$*"; }
fail() { printf '[MechOS AUR] ERROR: %s\n' "$*" >&2; exit 1; }

[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"
[ -s "$ARCHIVE" ] || fail "installed-system payload is missing: $ARCHIVE"

patch_tree() {
  local tree="$1"
  local bin="$tree/usr/local/bin"
  local apps="$tree/usr/share/applications"
  local update="$bin/mechos-update-center"
  mkdir -p "$bin" "$apps"

  cat > "$bin/mechos-aur" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

AUR_RPC="https://aur.archlinux.org/rpc/v5"
AUR_GIT="https://aur.archlinux.org"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/mechos/aur"

say() { printf '[MechOS AUR] %s\n' "$*"; }
fail() { say "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "Required command is missing: $1"; }
valid_pkg() { [[ "${1:-}" =~ ^[A-Za-z0-9@._+:-]+$ ]]; }

if [ "$(id -u)" -eq 0 ]; then
  fail "Do not run mechos-aur as root. AUR packages must be reviewed and built as your normal user."
fi

need curl
need git
need python3
need makepkg
need pacman
mkdir -p "$CACHE"

rpc() {
  local type="$1" arg="$2"
  python3 - "$type" "$arg" "$AUR_RPC" <<'PY'
import json, sys, urllib.parse, urllib.request
kind,arg,base=sys.argv[1:]
if kind=='search':
    url=base+'/search/'+urllib.parse.quote(arg)
elif kind=='info':
    url=base+'/info?arg[]='+urllib.parse.quote(arg)
else:
    raise SystemExit(2)
with urllib.request.urlopen(url, timeout=15) as r:
    data=json.load(r)
if kind=='search':
    rows=sorted(data.get('results',[]), key=lambda x:(-int(x.get('NumVotes',0)), x.get('Name','')))
    for row in rows[:50]:
        name=row.get('Name',''); ver=row.get('Version',''); desc=row.get('Description') or ''
        print(f'{name}\t{ver}\t{desc}')
else:
    rows=data.get('results',[])
    if not rows:
        raise SystemExit(3)
    row=rows[0]
    for key in ('Name','Version','Description','URL','Maintainer','LastModified','OutOfDate'):
        print(f'{key}: {row.get(key)}')
PY
}

repo_dir() { printf '%s/%s\n' "$CACHE" "$1"; }

sync_pkgbuild() {
  local pkg="$1" dir
  valid_pkg "$pkg" || fail "Invalid AUR package name: $pkg"
  dir="$(repo_dir "$pkg")"
  if [ -d "$dir/.git" ]; then
    git -C "$dir" fetch --quiet origin
    git -C "$dir" reset --hard --quiet origin/master 2>/dev/null || git -C "$dir" reset --hard --quiet origin/main
  else
    rm -rf "$dir"
    git clone --quiet "$AUR_GIT/$pkg.git" "$dir" || fail "Could not clone AUR package '$pkg'."
  fi
  [ -f "$dir/PKGBUILD" ] || fail "AUR package '$pkg' did not provide a PKGBUILD."
  printf '%s\n' "$dir"
}

review_pkgbuild() {
  local dir="$1"
  echo
  say "PKGBUILD review is required before installation."
  echo "----------------------------------------------------------------"
  sed -n '1,260p' "$dir/PKGBUILD"
  echo "----------------------------------------------------------------"
  echo
  read -r -p "Continue building this PKGBUILD? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { say "Cancelled."; exit 2; }
}

install_one() {
  local pkg="$1" dir
  dir="$(sync_pkgbuild "$pkg")"
  review_pkgbuild "$dir"
  say "Building $pkg as user $(id -un). Pacman may request administrator approval for dependencies/install."
  (cd "$dir" && makepkg -si --needed)
}

search_aur() {
  local term="${1:-}"
  [ -n "$term" ] || fail "Usage: mechos-aur search <term>"
  printf '%-36s %-24s %s\n' PACKAGE VERSION DESCRIPTION
  rpc search "$term" | while IFS=$'\t' read -r name ver desc; do
    printf '%-36s %-24s %s\n' "$name" "$ver" "$desc"
  done
}

info_aur() {
  local pkg="${1:-}"
  [ -n "$pkg" ] || fail "Usage: mechos-aur info <package>"
  valid_pkg "$pkg" || fail "Invalid AUR package name."
  rpc info "$pkg" || fail "AUR package '$pkg' was not found."
}

update_aur() {
  local pkgs=() pkg info
  mapfile -t pkgs < <(pacman -Qqm 2>/dev/null || true)
  [ "${#pkgs[@]}" -gt 0 ] || { say "No foreign/AUR packages are installed."; return 0; }
  say "Checking installed foreign packages against the AUR..."
  for pkg in "${pkgs[@]}"; do
    valid_pkg "$pkg" || continue
    if rpc info "$pkg" >/dev/null 2>&1; then
      say "AUR package detected: $pkg"
      install_one "$pkg"
    fi
  done
}

usage() {
  cat <<'TXT'
MechOS AUR Helper

Usage:
  mechos-aur search <term>       Search the Arch User Repository
  mechos-aur info <package>      Show AUR package information
  mechos-aur install <package>   Review, build and install an AUR package
  mechos-aur update              Rebuild/update installed AUR packages
  mechos-aur clean               Remove cached AUR build directories
  mechos-aur cache               Open the local AUR build cache

AUR packages are user-submitted. MechOS always shows the PKGBUILD before build
and never builds AUR packages as root.
TXT
}

case "${1:-}" in
  search) shift; search_aur "$*" ;;
  info) shift; info_aur "${1:-}" ;;
  install) shift; [ "$#" -eq 1 ] || fail "Usage: mechos-aur install <package>"; install_one "$1" ;;
  update) update_aur ;;
  clean) rm -rf "$CACHE"; mkdir -p "$CACHE"; say "AUR cache cleared." ;;
  cache) command -v dolphin >/dev/null 2>&1 && exec dolphin "$CACHE" || { printf '%s\n' "$CACHE"; } ;;
  help|-h|--help|'') usage ;;
  *) fail "Unknown command: $1. Run 'mechos-aur help'." ;;
esac
EOF
  chmod 755 "$bin/mechos-aur"

  cat > "$bin/mechos-aur-gui" <<'PY'
#!/usr/bin/env python3
import subprocess, sys
from pathlib import Path
from PyQt6.QtCore import Qt
from PyQt6.QtWidgets import QApplication, QFrame, QHBoxLayout, QInputDialog, QLabel, QMainWindow, QMessageBox, QPushButton, QVBoxLayout, QWidget

THEME=Path('/usr/share/mechos/theme/mechos-ui.qss')

def terminal(command):
    try:
        subprocess.Popen(['konsole','-e','bash','-lc',command+"; rc=$?; echo; echo 'Exit code:' $rc; read -rp 'Press Enter to close…'"])
    except Exception as exc:
        QMessageBox.warning(None,'MechOS AUR',str(exc))

class AurWindow(QMainWindow):
    def __init__(self):
        super().__init__(); self.setWindowTitle('MechOS AUR Packages'); self.resize(980,620)
        self.setStyleSheet((THEME.read_text() if THEME.is_file() else '') + 'QFrame#card{background:#09111f;border:1px solid #304064;border-radius:15px;}')
        root=QWidget(); self.setCentralWidget(root); outer=QVBoxLayout(root); outer.setContentsMargins(24,20,24,20); outer.setSpacing(14)
        h=QLabel('MECHOS  •  AUR PACKAGES'); h.setObjectName('purple'); outer.addWidget(h)
        hero=QFrame(); hero.setObjectName('card'); hl=QVBoxLayout(hero)
        t=QLabel('Arch User Repository Helper'); t.setObjectName('title'); hl.addWidget(t)
        d=QLabel('Search, review, build, and update AUR packages using the native MechOS helper. AUR packages are community-maintained and are not official Arch packages.'); d.setObjectName('muted'); d.setWordWrap(True); hl.addWidget(d); outer.addWidget(hero)
        row=QHBoxLayout()
        for title,detail,fn,primary in [
            ('Search AUR','Find community packages',self.search,True),
            ('Install Package','Review PKGBUILD then build',self.install,False),
            ('Update AUR Packages','Check installed foreign packages',lambda:terminal('mechos-aur update'),False),
            ('Open Build Cache','Inspect cached PKGBUILDs',lambda:subprocess.Popen(['mechos-aur','cache']),False),
        ]:
            b=QPushButton(title+'\n'+detail); b.setMinimumHeight(92); b.clicked.connect(fn)
            if primary: b.setObjectName('primary')
            row.addWidget(b,1)
        outer.addLayout(row)
        note=QLabel('Safety: MechOS refuses to build AUR packages as root and displays the PKGBUILD before installation.'); note.setObjectName('muted'); note.setWordWrap(True); outer.addWidget(note); outer.addStretch(1)
        close=QPushButton('Close'); close.clicked.connect(self.close); outer.addWidget(close,0,Qt.AlignmentFlag.AlignRight)
    def search(self):
        text,ok=QInputDialog.getText(self,'Search AUR','Search term:')
        if ok and text.strip(): terminal("mechos-aur search "+subprocess.list2cmdline([text.strip()]))
    def install(self):
        pkg,ok=QInputDialog.getText(self,'Install AUR Package','Exact package name:')
        if ok and pkg.strip(): terminal("mechos-aur install "+subprocess.list2cmdline([pkg.strip()]))

app=QApplication(sys.argv); app.setApplicationName('MechOS AUR Packages'); w=AurWindow(); w.show(); sys.exit(app.exec())
PY
  chmod 755 "$bin/mechos-aur-gui"

  cat > "$apps/mechos-aur.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MechOS AUR Packages
Comment=Search, review, build and update Arch User Repository packages
Exec=/usr/local/bin/mechos-aur-gui
Icon=system-software-install
Terminal=false
Categories=System;Settings;PackageManager;
Keywords=AUR;Arch;packages;PKGBUILD;
StartupNotify=true
EOF
  chmod 644 "$apps/mechos-aur.desktop"

  # Add an AUR entry to the final Update Center reference UI when available.
  if [ -f "$update" ]; then
    python3 - "$update" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); text=p.read_text(encoding='utf-8')
marker='# MECHOS_AUR_UPDATE_CENTER_V1'
if marker not in text:
    anchor='self.update_button.setEnabled(False); row.addWidget(self.update_button); copy.addLayout(row); hl.addLayout(copy,3)'
    if anchor in text:
        replacement='''self.update_button.setEnabled(False); row.addWidget(self.update_button)
        # MECHOS_AUR_UPDATE_CENTER_V1
        self.aur_button=QPushButton("AUR Packages"); self.aur_button.clicked.connect(lambda: subprocess.Popen(["/usr/local/bin/mechos-aur-gui"])); row.addWidget(self.aur_button)
        copy.addLayout(row); hl.addLayout(copy,3)'''
        text=text.replace(anchor,replacement,1)
    else:
        # Older layout fallback: insert immediately after the first Install Updates button declaration.
        anchor='self.update_button=QPushButton("Install Updates")'
        pos=text.find(anchor)
        if pos < 0:
            raise SystemExit('Update Center install button not found')
        end=text.find('\n',pos)
        addition='\n        # MECHOS_AUR_UPDATE_CENTER_V1\n        self.aur_button=QPushButton("AUR Packages"); self.aur_button.clicked.connect(lambda: subprocess.Popen(["/usr/local/bin/mechos-aur-gui"]))\n'
        text=text[:end]+addition+text[end:]
    p.write_text(text,encoding='utf-8')
PY
  fi

  bash -n "$bin/mechos-aur"
  python3 -m py_compile "$bin/mechos-aur-gui"
  [ ! -f "$update" ] || python3 -m py_compile "$update"
  grep -Fq 'PKGBUILD review is required' "$bin/mechos-aur" || fail "PKGBUILD review guard missing"
  grep -Fq 'Do not run mechos-aur as root' "$bin/mechos-aur" || fail "root build guard missing"
  grep -Fq 'makepkg -si --needed' "$bin/mechos-aur" || fail "makepkg install path missing"
}

patch_tree "$ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar --zstd -xf "$ARCHIVE" -C "$tmp"
patch_tree "$tmp"
new_archive="$ARCHIVE.aur-helper"
tar --zstd -cf "$new_archive" -C "$tmp" .
mv -f "$new_archive" "$ARCHIVE"
rm -rf "$tmp"
trap - EXIT

log "Native MechOS AUR helper, GUI and Update Center entry added"
