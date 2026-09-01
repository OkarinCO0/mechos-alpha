#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
PAYLOAD="$ROOT/usr/share/mechos/install-payload"
ARCHIVE="$PAYLOAD/mechos-rootfs.tar.zst"

log() { printf '[MechOS Optimization UI] %s\n' "$*"; }
fail() { printf '[MechOS Optimization UI] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Optimization UI] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"

patch_tree() {
  local tree="$1"
  local bin="$tree/usr/local/bin"
  local perf="$bin/mechos-performance-center"
  local tools="$bin/mechos-system-tools"

  [ -f "$perf" ] || fail "Performance Center is missing from $tree"
  [ -f "$bin/mechos-optimization-report" ] || fail "Optimization report command is missing from $tree"

  python3 - "$perf" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = "# MECHOS_OPTIMIZATION_REPORT_BUTTON_V1"

if marker not in text:
    anchor = '("📊 System Monitor", lambda: run(["konsole", "-e", "btop"])),\n'
    if anchor not in text:
        raise SystemExit(f"Could not locate Performance Center action grid in {path}")

    addition = '''("📊 System Monitor", lambda: run(["konsole", "-e", "btop"])),
            # MECHOS_OPTIMIZATION_REPORT_BUTTON_V1
            ("🧪 Run Optimization Report", lambda: run([
                "konsole", "-e", "bash", "-lc",
                "/usr/local/bin/mechos-optimization-report; rc=$?; echo; "
                "echo 'Latest optimization reports:'; "
                "ls -1t \\\"${XDG_STATE_HOME:-$HOME/.local/state}/mechos\\\"/optimization-report-*.txt 2>/dev/null | head -n 3 || true; "
                "echo; echo \\\"Report exit code: $rc\\\"; read -rp 'Press Enter to close...'"
            ])),
            ("📂 Open Report Folder", lambda: run([
                "bash", "-lc",
                "mkdir -p \\\"${XDG_STATE_HOME:-$HOME/.local/state}/mechos\\\"; "
                "exec dolphin \\\"${XDG_STATE_HOME:-$HOME/.local/state}/mechos\\\""
            ])),
'''
    text = text.replace(anchor, addition, 1)
    path.write_text(text, encoding="utf-8")
PY

  # The System Tools Hub used to launch the report directly with no visible
  # output. Run it in Konsole so users can see the diagnostics and saved path.
  if [ -f "$tools" ]; then
    python3 - "$tools" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = '("OPTIMIZATION REPORT", "Measure boot time, idle RAM/load, services and the largest memory consumers.", ["/usr/local/bin/mechos-optimization-report"]),'
new = '("OPTIMIZATION REPORT", "Measure boot time, idle RAM/load, services and the largest memory consumers.", ["konsole", "-e", "bash", "-lc", "/usr/local/bin/mechos-optimization-report; echo; read -rp \'Press Enter to close...\'"]),'
if old in text:
    text = text.replace(old, new, 1)
elif new not in text:
    raise SystemExit(f"Could not locate Optimization Report tool entry in {path}")
path.write_text(text, encoding="utf-8")
PY
  fi

  python3 -m py_compile "$perf"
  grep -Fq '# MECHOS_OPTIMIZATION_REPORT_BUTTON_V1' "$perf" \
    || fail "Optimization Report button marker is missing from Performance Center"
  grep -Fq 'Run Optimization Report' "$perf" \
    || fail "Run Optimization Report action is missing from Performance Center"
  grep -Fq 'Open Report Folder' "$perf" \
    || fail "Open Report Folder action is missing from Performance Center"

  if [ -f "$tools" ]; then
    python3 -m py_compile "$tools"
    grep -Fq 'konsole", "-e", "bash", "-lc", "/usr/local/bin/mechos-optimization-report' "$tools" \
      || fail "System Tools Optimization Report is not wired to visible output"
  fi
}

patch_tree "$ROOT"

# UI polish is applied after the installed-system archive exists. Patch the
# installed payload as well so the installed Performance Center matches Live.
if [ -s "$ARCHIVE" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  tar --zstd -xf "$ARCHIVE" -C "$tmp"
  patch_tree "$tmp"
  new_archive="$ARCHIVE.optimization-ui"
  tar --zstd -cf "$new_archive" -C "$tmp" .
  mv -f "$new_archive" "$ARCHIVE"
  rm -rf "$tmp"
  trap - EXIT
else
  fail "installed-system payload archive is missing: $ARCHIVE"
fi

log "Optimization Report is now visible from Performance Center and System Tools"
