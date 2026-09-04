#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"

log(){ printf '[MechOS Creator Shortcuts] %s\n' "$*"; }
fail(){ printf '[MechOS Creator Shortcuts] ERROR: %s\n' "$*" >&2; exit 1; }

patch_file(){
  local file="$1"
  [ -f "$file" ] || fail "Creator UI missing: $file"

  python3 - "$file" <<'PY'
from pathlib import Path
import sys

p=Path(sys.argv[1])
t=p.read_text(encoding='utf-8')
marker='# MECHOS_LIVE_CREATOR_SHORTCUTS_V1'
if marker in t:
    raise SystemExit(0)

old='''        shortcuts = [\n            ("New Project", "Project manager", lambda: self.owner.select(1)),\n            ("Open Project", "Browse real projects", lambda: self.owner.select(1)),\n            ("Project Manager", "Manage projects", lambda: self.owner.select(1)),\n            ("Asset Browser", "Creator assets", lambda: self.owner.select(5)),\n            ("MechClip AI", "Open clipping tools", lambda: self.owner.select(6)),\n            ("Creator Settings", "Preferences", lambda: self.owner.select(9)),\n        ]\n'''
new='''        # MECHOS_LIVE_CREATOR_SHORTCUTS_V1\n        # These are native controls with distinct runtime actions, not labels\n        # copied from the reference artwork.\n        shortcuts = [\n            ("New Project", "Create a real project", self.new_project_shortcut),\n            ("Open Project", "Choose a project on this PC", self.open_project_shortcut),\n            ("Project Manager", "Manage detected projects", self.project_manager_shortcut),\n            ("Asset Browser", "Browse creator assets", self.asset_browser_shortcut),\n            ("MechClip AI", "Open clipping tools", self.mechclip_shortcut),\n            ("Creator Settings", "Creator preferences", self.creator_settings_shortcut),\n        ]\n'''
if old not in t:
    raise SystemExit('[MechOS Creator Shortcuts] shortcut block anchor not found')
t=t.replace(old,new,1)

anchor='''    def tool_action(self, action):\n'''
methods=r'''    def new_project_shortcut(self):
        """Start the real Creator project workflow when the owner provides it."""
        fn = getattr(self.owner, "new_project", None)
        if callable(fn):
            try:
                result = fn()
                if result is not None:
                    return result
                return
            except Exception:
                pass
        # The Projects page is the safe fallback and never invents project data.
        self.owner.select(1)

    def open_project_shortcut(self):
        """Choose an existing local project and open it through the real launcher."""
        from PyQt6.QtWidgets import QFileDialog, QMessageBox

        start = str(Path.home() / "Projects") if (Path.home() / "Projects").is_dir() else str(Path.home())
        path = QFileDialog.getExistingDirectory(self, "Open Creator Project", start)
        if not path:
            return
        project = Path(path)
        kind = None
        if (project / "ProjectSettings" / "ProjectVersion.txt").is_file():
            kind = "Unity"
        elif (project / "project.godot").is_file():
            kind = "Godot"
        elif any(project.glob("*.uproject")):
            kind = "Unreal"
        else:
            blends = list(project.glob("*.blend"))
            if blends:
                blend = max(blends, key=lambda f: f.stat().st_mtime)
                if shutil.which("blender"):
                    try:
                        subprocess.Popen(["blender", str(blend)])
                        return
                    except Exception:
                        pass
            QMessageBox.information(
                self,
                "MechOS Creator Mode",
                "That folder does not contain a detected Unity, Unreal, Godot, or Blender project.",
            )
            return
        try:
            stamp = project.stat().st_mtime
        except OSError:
            stamp = 0
        _launch_project((stamp, project, kind), self.owner)
        self.refresh_projects()

    def project_manager_shortcut(self):
        self.refresh_projects()
        self.owner.select(1)

    def asset_browser_shortcut(self):
        self.owner.select(5)

    def mechclip_shortcut(self):
        self.owner.select(6)

    def creator_settings_shortcut(self):
        self.owner.select(9)

'''
if anchor not in t:
    raise SystemExit('[MechOS Creator Shortcuts] method insertion anchor not found')
t=t.replace(anchor,methods+anchor,1)
compile(t,str(p),'exec')
p.write_text(t,encoding='utf-8')
PY

  PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$file" || fail "Creator UI Python validation failed"
  grep -Fq 'MECHOS_LIVE_CREATOR_SHORTCUTS_V1' "$file" || fail "live shortcut marker missing"
  grep -Fq 'getExistingDirectory' "$file" || fail "Open Project chooser missing"
  grep -Fq 'new_project_shortcut' "$file" || fail "New Project action missing"
}

patch_tree(){
  local tree="$1"
  patch_file "$tree/usr/local/share/mechos/ui/creator_shell.py"
}

patch_tree "$ROOT"

if [ -s "$ARCHIVE" ]; then
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  tar --zstd -xpf "$ARCHIVE" -C "$tmp"
  patch_tree "$tmp"
  replacement="$ARCHIVE.creator-shortcuts"
  tar --zstd -cpf "$replacement" -C "$tmp" .
  mv -f "$replacement" "$ARCHIVE"
  rm -rf "$tmp"; trap - EXIT
fi

log 'Creator shortcuts are live: New/Open Project, Project Manager, Asset Browser, MechClip AI and Creator Settings'
