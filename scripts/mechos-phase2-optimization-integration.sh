#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${1:-final}"
ROOT="/workspace/archlive/airootfs"
PAYLOAD="$ROOT/usr/share/mechos/install-payload"
ARCHIVE="$PAYLOAD/mechos-rootfs.tar.zst"
POSTINSTALL="$PAYLOAD/mechos-postinstall-target"
PROFILE="/workspace/archlive/profiledef.sh"

log() { printf '[MechOS Phase2] %s\n' "$*"; }
fail() { printf '[MechOS Phase2] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[MechOS Phase2] ERROR: line %s failed: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2' ERR

[ "$PHASE" = "final" ] || exit 0
[ -d "$ROOT" ] || fail "ArchISO rootfs is missing: $ROOT"

patch_tree() {
  local tree="$1"
  local bin="$tree/usr/local/bin"
  local apps="$tree/usr/share/applications"
  local systemd_dir="$tree/etc/systemd/system"
  local unit="$systemd_dir/mechos-firstboot.service"
  local timer="$systemd_dir/mechos-firstboot.timer"
  local session="$bin/mechos-gaming-session"
  local diag="$bin/mechos-boot-diagnostics"
  local monitor="$bin/mechos-handoff-monitor"

  mkdir -p "$bin" "$apps" "$systemd_dir" "$systemd_dir/timers.target.wants"

  # Phase 2: deferred first-boot work must never hold graphical.target open.
  # The timer itself waits until graphical.target is active, then gives the
  # desktop two seconds to settle before launching low-priority setup work.
  cat > "$unit" <<'FIRSTBOOT_EOF'
[Unit]
Description=MechOS background first-boot gaming and GPU setup
After=NetworkManager.service
Wants=NetworkManager.service
ConditionPathExists=!/run/archiso/bootmnt
ConditionPathExists=/var/lib/mechos/oobe-complete
ConditionPathExists=!/var/lib/mechos/firstboot.done

[Service]
Type=oneshot
ExecStart=/usr/local/bin/mechos-firstboot
TimeoutStartSec=5min
Nice=15
IOSchedulingClass=idle
CPUWeight=10
IOWeight=10
FIRSTBOOT_EOF

  cat > "$timer" <<'TIMER_EOF'
[Unit]
Description=Start MechOS first-boot work after the graphical session is ready
After=graphical.target
ConditionPathExists=!/run/archiso/bootmnt
ConditionPathExists=/var/lib/mechos/oobe-complete
ConditionPathExists=!/var/lib/mechos/firstboot.done

[Timer]
OnActiveSec=2s
AccuracySec=250ms
Unit=mechos-firstboot.service

[Install]
WantedBy=timers.target
TIMER_EOF

  # Remove older service enablement links and enable only the non-blocking timer.
  rm -f \
    "$systemd_dir/graphical.target.wants/mechos-firstboot.service" \
    "$systemd_dir/multi-user.target.wants/mechos-firstboot.service" \
    "$systemd_dir/default.target.wants/mechos-firstboot.service" 2>/dev/null || true
  ln -sfn ../mechos-firstboot.timer "$systemd_dir/timers.target.wants/mechos-firstboot.timer"

  cat > "$monitor" <<'MONITOR_EOF'
#!/usr/bin/env bash
set +e

METRICS="${1:-${XDG_STATE_HOME:-$HOME/.local/state}/mechos/gaming-launch.metrics}"
STATE_DIR="$(dirname "$METRICS")"
mkdir -p "$STATE_DIR"

# Only one monitor should annotate a launch at a time.
exec 9>"$STATE_DIR/handoff-monitor.lock"
if command -v flock >/dev/null 2>&1; then
  flock -n 9 || exit 0
fi

uptime_ms() {
  awk '{printf "%.0f\n", $1 * 1000}' /proc/uptime 2>/dev/null
}

START_MS="$(uptime_ms)"
[ -n "$START_MS" ] || exit 0
GAMESCOPE_MS=""
STEAM_MS=""
UI_MS=""
START_WALL=$SECONDS

while (( SECONDS - START_WALL < 15 )); do
  NOW_MS="$(uptime_ms)"
  if [ -z "$GAMESCOPE_MS" ] && pgrep -x gamescope >/dev/null 2>&1; then
    GAMESCOPE_MS="$NOW_MS"
  fi
  if [ -z "$STEAM_MS" ] && pgrep -x steam >/dev/null 2>&1; then
    STEAM_MS="$NOW_MS"
  fi
  if [ -z "$UI_MS" ] && pgrep -f '[s]teamwebhelper' >/dev/null 2>&1; then
    UI_MS="$NOW_MS"
  fi
  [ -n "$GAMESCOPE_MS" ] && [ -n "$STEAM_MS" ] && [ -n "$UI_MS" ] && break
  sleep 0.05
done

append_delta() {
  local name="$1" value="$2"
  if [ -n "$value" ]; then
    printf '%s=%s\n' "$name" "$((value - START_MS))" >> "$METRICS"
  fi
}

printf 'phase2_monitor_start_uptime_ms=%s\n' "$START_MS" >> "$METRICS"
append_delta gamescope_detect_ms "$GAMESCOPE_MS"
append_delta steam_detect_ms "$STEAM_MS"
append_delta steam_ui_detect_ms "$UI_MS"

FINAL_MS="$UI_MS"
[ -n "$FINAL_MS" ] || FINAL_MS="$STEAM_MS"
[ -n "$FINAL_MS" ] || FINAL_MS="$GAMESCOPE_MS"
if [ -n "$FINAL_MS" ]; then
  printf 'handoff_total_ms=%s\n' "$((FINAL_MS - START_MS))" >> "$METRICS"
else
  printf 'handoff_total_ms=unavailable\n' >> "$METRICS"
fi
MONITOR_EOF
  chmod 755 "$monitor"

  if [ -f "$session" ]; then
    python3 - "$session" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = "# MECHOS_PHASE2_HANDOFF_TELEMETRY"
if marker not in text:
    needle = '} > "$STATE_DIR/gaming-launch.metrics"\n'
    if needle not in text:
        raise SystemExit(f"Could not locate FastBoot metrics write in {path}")
    addition = needle + '''\n# MECHOS_PHASE2_HANDOFF_TELEMETRY\nif [ -x /usr/local/bin/mechos-handoff-monitor ]; then\n  /usr/local/bin/mechos-handoff-monitor "$STATE_DIR/gaming-launch.metrics" >/dev/null 2>&1 &\nfi\n'''
    text = text.replace(needle, addition, 1)
    path.write_text(text, encoding="utf-8")
PY
  fi

  cat > "$diag" <<'DIAG_EOF'
#!/usr/bin/env bash
set +e

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mechos"
mkdir -p "$STATE_DIR"
REPORT="$STATE_DIR/optimization-report-$(date +%Y%m%d-%H%M%S).txt"
exec > >(tee "$REPORT") 2>&1

section() { printf '\n--- %s ---\n' "$1"; }

read_cpu() {
  awk '/^cpu / { idle=$5+$6; total=0; for (i=2;i<=NF;i++) total+=$i; print total, idle; exit }' /proc/stat 2>/dev/null
}

cpu_busy_percent() {
  local t1 i1 t2 i2 dt di
  read -r t1 i1 < <(read_cpu)
  sleep 0.5
  read -r t2 i2 < <(read_cpu)
  dt=$((t2-t1)); di=$((i2-i1))
  if [ "$dt" -gt 0 ]; then
    awk -v dt="$dt" -v di="$di" 'BEGIN { printf "%.1f", (100.0*(dt-di))/dt }'
  else
    printf '0.0'
  fi
}

echo "=== MechOS Phase 2 Optimization Report ==="
echo "Generated: $(date -Is)"
echo "Report: $REPORT"

section "Boot timing"
systemd-analyze time 2>&1 || true

section "Ten slowest startup units"
systemd-analyze blame --no-pager 2>&1 | head -n 10 || true

section "Graphical critical chain"
systemd-analyze critical-chain graphical.target 2>&1 || true

section "Boot score"
GRAPHICAL_SEC="$(systemd-analyze critical-chain graphical.target 2>/dev/null | sed -n 's/^graphical.target @\([0-9.]*\)s.*/\1/p' | head -n1)"
BOOT_GRADE="N/A"
if [ -n "$GRAPHICAL_SEC" ]; then
  if awk -v s="$GRAPHICAL_SEC" 'BEGIN {exit !(s <= 5.0)}'; then BOOT_GRADE="A"
  elif awk -v s="$GRAPHICAL_SEC" 'BEGIN {exit !(s <= 7.0)}'; then BOOT_GRADE="B"
  elif awk -v s="$GRAPHICAL_SEC" 'BEGIN {exit !(s <= 10.0)}'; then BOOT_GRADE="C"
  else BOOT_GRADE="D"; fi
fi
printf 'graphical_target_seconds=%s\n' "${GRAPHICAL_SEC:-unavailable}"
printf 'boot_grade=%s\n' "$BOOT_GRADE"
printf 'failed_unit_count='
systemctl --failed --no-legend 2>/dev/null | awk 'NF {n++} END {print n+0}'

section "MechScope handoff"
if [ -s "$STATE_DIR/gaming-launch.metrics" ]; then
  cat "$STATE_DIR/gaming-launch.metrics"
  HANDOFF="$(awk -F= '$1=="handoff_total_ms" {v=$2} END {print v}' "$STATE_DIR/gaming-launch.metrics")"
  if [[ "$HANDOFF" =~ ^[0-9]+$ ]]; then
    if [ "$HANDOFF" -le 3000 ]; then echo 'handoff_grade=A'
    elif [ "$HANDOFF" -le 5000 ]; then echo 'handoff_grade=B'
    elif [ "$HANDOFF" -le 8000 ]; then echo 'handoff_grade=C'
    else echo 'handoff_grade=D'; fi
  else
    echo 'handoff_grade=NOT_MEASURED'
  fi
else
  echo "No Gaming Mode handoff metrics recorded yet."
  echo 'handoff_grade=NOT_MEASURED'
fi

section "System activity snapshot"
CPU_BUSY="$(cpu_busy_percent)"
LOAD1="$(awk '{print $1}' /proc/loadavg 2>/dev/null)"
CORES="$(nproc 2>/dev/null || echo 1)"
TOP_CPU="$(ps -eo pcpu= --sort=-pcpu 2>/dev/null | awk 'NR==1 {print $1+0}')"
SYSTEM_STATE="IDLE"
if awk -v c="$CPU_BUSY" 'BEGIN {exit !(c >= 20.0)}' || \
   awk -v p="${TOP_CPU:-0}" 'BEGIN {exit !(p >= 50.0)}' || \
   awk -v l="${LOAD1:-0}" -v n="$CORES" 'BEGIN {exit !(l >= n*0.75)}'; then
  SYSTEM_STATE="BUSY"
fi
printf 'system_state=%s\n' "$SYSTEM_STATE"
printf 'cpu_busy_percent=%s\n' "$CPU_BUSY"
printf 'logical_cpus=%s\n' "$CORES"
printf 'load_average='
cat /proc/loadavg 2>/dev/null || true
printf 'highest_process_cpu_percent=%s\n' "${TOP_CPU:-0}"
printf 'running_services='
systemctl list-units --type=service --state=running --no-legend 2>/dev/null | wc -l
free -h 2>/dev/null || true
df -h / 2>/dev/null || true

section "Top CPU consumers"
ps -eo pid,comm,%cpu,%mem,rss --sort=-%cpu 2>/dev/null | head -n 12 || true

section "Top memory consumers"
ps -eo pid,comm,%cpu,%mem,rss --sort=-rss 2>/dev/null | head -n 12 || true

section "Failed units"
systemctl --failed --no-pager 2>&1 || true

section "Wait-online status"
systemctl is-enabled NetworkManager-wait-online.service 2>&1 || true
systemctl status NetworkManager-wait-online.service --no-pager -n 0 2>&1 || true

section "OOBE / background firstboot"
for marker in /var/lib/mechos/installed /var/lib/mechos/oobe-complete /var/lib/mechos/firstboot.done; do
  if [ -e "$marker" ]; then echo "[OK] $marker"; else echo "[MISSING] $marker"; fi
done
systemctl --no-pager --full status mechos-firstboot.timer 2>&1 || true
systemctl --no-pager --full status mechos-firstboot.service 2>&1 || true

section "SDDM startup"
systemctl --no-pager --full status sddm.service 2>&1 || true

section "GPU"
lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' || true

section "Initramfs audit"
if [ -f /etc/mkinitcpio.conf ]; then
  grep -E '^[[:space:]]*(MODULES|HOOKS|COMPRESSION|COMPRESSION_OPTIONS)=' /etc/mkinitcpio.conf 2>/dev/null || true
fi
for f in /boot/initramfs-linux*.img; do
  [ -f "$f" ] || continue
  stat -c '%n size_bytes=%s modified=%y' "$f" 2>/dev/null || true
done

section "Cached preflight"
if [ -f "$STATE_DIR/gaming-preflight.ok" ]; then
  stat "$STATE_DIR/gaming-preflight.ok" 2>/dev/null || true
  printf 'signature='
  cat "$STATE_DIR/gaming-preflight.signature" 2>/dev/null || true
else
  echo "No successful Gaming Mode preflight has been cached yet."
fi

section "Gaming session log"
tail -n 120 "$STATE_DIR/gaming-session.log" 2>/dev/null || true

section "MechScope log"
tail -n 120 "$STATE_DIR/mechscope.log" 2>/dev/null || true

printf '\nOptimization report saved to: %s\n' "$REPORT"
DIAG_EOF
  chmod 755 "$diag"
  ln -sfn mechos-boot-diagnostics "$bin/mechos-optimization-report"

  cat > "$apps/mechos-boot-diagnostics.desktop" <<'DESKTOP_EOF'
[Desktop Entry]
Type=Application
Name=MechOS Phase 2 Optimization Report
Comment=Measure boot, MechScope handoff, system activity, services and startup bottlenecks
Exec=konsole -e bash -lc '/usr/local/bin/mechos-optimization-report; echo; read -rp "Press Enter to close..."'
Icon=utilities-system-monitor
Terminal=false
Categories=System;Settings;
Keywords=MechOS;Optimization;Performance;Boot;MechScope;Diagnostics;
DESKTOP_EOF
}

patch_tree "$ROOT"

if [ -s "$ARCHIVE" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  tar --zstd -xf "$ARCHIVE" -C "$tmp"
  patch_tree "$tmp"
  new_archive="$ARCHIVE.phase2"
  tar --zstd -cf "$new_archive" -C "$tmp" .
  mv -f "$new_archive" "$ARCHIVE"
  rm -rf "$tmp"
  trap - EXIT
else
  fail "installed-system payload archive is missing: $ARCHIVE"
fi

# The native installer is generated after FastBoot. Make new installations
# enable the timer instead of re-enabling the old graphical dependency.
NATIVE_HELPER="$ROOT/usr/local/libexec/mechos-native-install-helper"
if [ -f "$NATIVE_HELPER" ]; then
  sed -i 's/mechos-firstboot\.service/mechos-firstboot.timer/g' "$NATIVE_HELPER"
  bash -n "$NATIVE_HELPER" || fail "native installer helper syntax validation failed"
  grep -Fq 'mechos-firstboot.timer' "$NATIVE_HELPER" \
    || fail "native installer does not enable the Phase 2 firstboot timer"
fi

# Preserve a visible boot menu while cutting the default wait from six seconds
# to two seconds. Users can still select alternate/dual-boot entries normally.
if [ -f "$POSTINSTALL" ]; then
  sed -i 's/GRUB_TIMEOUT=6/GRUB_TIMEOUT=2/g' "$POSTINSTALL"
  bash -n "$POSTINSTALL" || fail "post-install syntax failed after Phase 2 bootloader tuning"
fi

if [ -f "$PROFILE" ]; then
  for path in \
    /usr/local/bin/mechos-handoff-monitor \
    /usr/local/bin/mechos-boot-diagnostics; do
    if ! grep -Fq "file_permissions[\"$path\"]" "$PROFILE"; then
      printf '\nfile_permissions["%s"]="0:0:755"\n' "$path" >> "$PROFILE"
    fi
  done
fi

bash -n "$ROOT/usr/local/bin/mechos-handoff-monitor" || fail "handoff monitor syntax validation failed"
bash -n "$ROOT/usr/local/bin/mechos-boot-diagnostics" || fail "Phase 2 diagnostics syntax validation failed"
[ -L "$ROOT/etc/systemd/system/timers.target.wants/mechos-firstboot.timer" ] \
  || fail "Phase 2 firstboot timer is not enabled"
[ ! -e "$ROOT/etc/systemd/system/graphical.target.wants/mechos-firstboot.service" ] \
  || fail "old graphical firstboot dependency still exists"
grep -Fq '# MECHOS_PHASE2_HANDOFF_TELEMETRY' "$ROOT/usr/local/bin/mechos-gaming-session" \
  || fail "Phase 2 MechScope telemetry hook is missing"
grep -Fq 'system_state=' "$ROOT/usr/local/bin/mechos-boot-diagnostics" \
  || fail "busy/idle activity classification is missing"
grep -Fq 'boot_grade=' "$ROOT/usr/local/bin/mechos-boot-diagnostics" \
  || fail "boot score is missing"

log "Phase 2 applied: non-blocking firstboot timer, 2s boot menu, MechScope handoff timing, activity classification and boot scoring"
