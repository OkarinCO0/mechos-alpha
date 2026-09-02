#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
ARCHIVE="$ROOT/usr/share/mechos/install-payload/mechos-rootfs.tar.zst"

log() { printf '[MechOS Creator Launch] %s\n' "$*"; }
fail() { printf '[MechOS Creator Launch] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Creator Launch] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"
[ -s "$ARCHIVE" ] || fail "installed-system payload is missing: $ARCHIVE"

patch_tree() {
  local tree="$1"
  local bin="$tree/usr/local/bin"
  local units="$tree/usr/lib/systemd/user"
  local layer="$bin/mechos-gaming-layer"
  local control="$bin/mechos-gaming-layer-control"

  mkdir -p "$units"

  cat > "$units/mechos-creator-mode.service" <<'UNIT'
[Unit]
Description=MechOS Creator Mode
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
Environment=MECHOS_MODE=creator
ExecStart=/usr/local/bin/mechos-creator-mode
Restart=no
TimeoutStopSec=8
KillMode=control-group

[Install]
WantedBy=default.target
UNIT

  [ -f "$layer" ] || fail "gaming layer is missing in $tree"
  [ -f "$control" ] || fail "gaming layer control is missing in $tree"

  python3 - "$layer" "$control" <<'PY'
from pathlib import Path
import sys

layer = Path(sys.argv[1])
control = Path(sys.argv[2])

# A Creator process started with nohup from inside mechos-gaming-layer remains
# in that service's cgroup. When the gaming-layer service exits, systemd may
# kill the newly launched Creator process. Start Creator Mode as its own user
# service instead so it survives the MechScope layer shutting down.
text = layer.read_text(encoding="utf-8")
old = '''    if [ -x /usr/local/bin/mechos-creator-mode ]; then
      nohup /usr/local/bin/mechos-creator-mode >>"$CREATOR_LOG" 2>&1 </dev/null &
    fi
    exit 0
'''
new = '''    if [ -x /usr/local/bin/mechos-creator-mode ]; then
      if systemctl --user cat mechos-creator-mode.service >/dev/null 2>&1; then
        systemctl --user reset-failed mechos-creator-mode.service >/dev/null 2>&1 || true
        systemctl --user start --no-block mechos-creator-mode.service
      else
        # Fallback for unusual sessions without the installed unit. systemd-run
        # still creates a separate user-service cgroup instead of inheriting the
        # gaming-layer cgroup.
        systemd-run --user --quiet --collect --unit=mechos-creator-mode \
          /usr/local/bin/mechos-creator-mode >/dev/null 2>&1 || true
      fi
    fi
    exit 0
'''
if old not in text and 'systemctl --user start --no-block mechos-creator-mode.service' not in text:
    raise SystemExit('[MechOS Creator Launch] creator handoff block was not found in gaming layer')
if old in text:
    text = text.replace(old, new, 1)
layer.write_text(text, encoding="utf-8")

text = control.read_text(encoding="utf-8")
old = '''  creator)
    stop_layer
    if [ -x /usr/local/bin/mechos-creator-mode ]; then
      nohup /usr/local/bin/mechos-creator-mode >>"$STATE_DIR/creator-mode.log" 2>&1 </dev/null &
    fi
    ;;
'''
new = '''  creator)
    # Start Creator Mode in a separate systemd user unit FIRST. Stopping the
    # gaming layer afterwards cannot kill Creator Mode because it is no longer
    # in the gaming layer's cgroup.
    if [ -x /usr/local/bin/mechos-creator-mode ]; then
      if systemctl --user cat mechos-creator-mode.service >/dev/null 2>&1; then
        systemctl --user reset-failed mechos-creator-mode.service >/dev/null 2>&1 || true
        systemctl --user start --no-block mechos-creator-mode.service
      else
        systemd-run --user --quiet --collect --unit=mechos-creator-mode \
          /usr/local/bin/mechos-creator-mode >/dev/null 2>&1 || true
      fi
    fi
    stop_layer
    ;;
'''
if old not in text and 'Start Creator Mode in a separate systemd user unit FIRST' not in text:
    raise SystemExit('[MechOS Creator Launch] creator control block was not found')
if old in text:
    text = text.replace(old, new, 1)
control.write_text(text, encoding="utf-8")
PY

  chmod 755 "$layer" "$control"
  bash -n "$layer" || fail "gaming-layer syntax failed"
  bash -n "$control" || fail "gaming-layer-control syntax failed"

  grep -Fq 'systemctl --user start --no-block mechos-creator-mode.service' "$layer" \
    || fail "gaming layer does not launch Creator Mode through its own user service"
  grep -Fq 'systemctl --user start --no-block mechos-creator-mode.service' "$control" \
    || fail "mode switch control does not launch Creator Mode through its own user service"
  grep -Fq 'ExecStart=/usr/local/bin/mechos-creator-mode' "$units/mechos-creator-mode.service" \
    || fail "Creator Mode user unit is invalid"

  # On the installed payload Creator Mode must exist. Live may intentionally
  # omit it because Creator Mode is post-install-only.
  if [ -e "$tree/var/lib/mechos/installed" ] || [ "$tree" != "$ROOT" ]; then
    [ -x "$bin/mechos-creator-mode" ] || fail "installed payload is missing Creator Mode"
    if [ -f "$bin/mechos-creator-mode.real" ]; then
      PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$bin/mechos-creator-mode.real" \
        || fail "Creator Mode real application failed Python validation"
    elif head -n1 "$bin/mechos-creator-mode" | grep -q python; then
      PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$bin/mechos-creator-mode" \
        || fail "Creator Mode application failed Python validation"
    fi
  fi
}

patch_tree "$ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar --zstd -xf "$ARCHIVE" -C "$tmp"
patch_tree "$tmp"
replacement="$ARCHIVE.creator-launch"
tar --zstd -cpf "$replacement" -C "$tmp" .
mv -f "$replacement" "$ARCHIVE"
rm -rf "$tmp"
trap - EXIT

# The service file must be part of the installed rootfs archive.
tar --zstd -tf "$ARCHIVE" './usr/lib/systemd/user/mechos-creator-mode.service' >/dev/null \
  || fail "installed payload lost Creator Mode user service"

log "Creator Mode handoff fixed: it now runs in its own user service and survives MechScope/gaming-layer shutdown"
