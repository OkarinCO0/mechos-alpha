#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOTFIX="$ROOT/scripts/mechos-installer-auto-reboot-hotfix.sh"
INSTALLER="$ROOT/overlay/rootfs/usr/local/bin/mechos-install"
PATCHER="$ROOT/scripts/patch-mechos-reference-v5.py"

fail(){ echo "[validate-installer-auto-reboot] ERROR: $*" >&2; exit 1; }

[ -f "$HOTFIX" ] || fail "auto-reboot hotfix missing"
[ -f "$INSTALLER" ] || fail "canonical Live installer backend missing"
bash -n "$HOTFIX" || fail "auto-reboot hotfix shell syntax failed"
bash -n "$INSTALLER" || fail "canonical Live installer shell syntax failed"

for file in "$HOTFIX" "$INSTALLER"; do
  grep -Fq 'MECHOS_INSTALL_SUCCESS_AUTO_REBOOT_V1' "$file" || fail "success-only reboot marker missing from $file"
  grep -Fq 'systemctl reboot' "$file" || fail "reboot command missing from $file"
  grep -Fq 'Press Ctrl+C' "$file" || fail "Live-session escape notice missing from $file"
  grep -Fq 'for remaining in 10 9 8 7 6 5 4 3 2 1' "$file" || fail "visible reboot countdown missing from $file"
done

grep -Fq 'install_rc=$?' "$INSTALLER" || fail "canonical installer does not capture archinstall result"
grep -Fq 'if [[ "$install_rc" -ne 0 ]]' "$INSTALLER" || fail "canonical installer has no failure/cancel guard"
grep -Fq 'archinstall --config "$CONFIG"' "$INSTALLER" || fail "canonical configured archinstall path missing"
if grep -Eq '^[[:space:]]*exec[[:space:]]+archinstall([[:space:]]|$)' "$INSTALLER"; then
  fail "canonical installer still execs archinstall and cannot run post-success policy"
fi

grep -Fq 'MECHOS_ARCHLIVE_ROOT' "$HOTFIX" || fail "final reboot guard cannot be exercised against an isolated generated root"
grep -Fq 'FINAL INSTALLER TAIL AUTHORITY' "$HOTFIX" || fail "tail-authoritative generated installer repair missing"
grep -Fq 'SERVER_PID=' "$HOTFIX" || fail "generated installer signature check missing"
grep -Fq 'candidates[-1]' "$HOTFIX" || fail "final Archinstall command selection missing"
grep -Fq 'no supported Archinstall execution path found' "$HOTFIX" || fail "final repair diagnostic missing"
grep -Fq 'mechos-installer-auto-reboot-hotfix.sh' "$PATCHER" || fail "auto-reboot hotfix is not wired into final build chain"

# Reproduce the full installer produced by build-mechos-archiso.sh, but use a
# deliberately different completion message. The repair must depend only on the
# generated-installer signature + final Archinstall command, never on exact
# success wording.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/usr/local/bin"
cat > "$tmp/usr/local/bin/mechos-install" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
PAYLOAD_DIR="/usr/share/mechos/install-payload"
CONFIG="$PAYLOAD_DIR/archinstall-mechos.json"
SERVER_PID=4242
PAYLOAD_SENTINEL="payload-server-and-hardware-scan-must-survive"

echo "$PAYLOAD_SENTINEL" >/dev/null
# mechos-postinstall-target is served by the loopback payload server.
trap 'true' EXIT INT TERM

# Do NOT use --silent. The user still chooses the disk, filesystem,
# bootloader, username/password and confirms all destructive actions.
archinstall --config "$CONFIG"

echo "THIS COMPLETION TEXT IS INTENTIONALLY DIFFERENT"
echo "A future installer pass may rewrite these words again."
EOF
chmod 0755 "$tmp/usr/local/bin/mechos-install"

MECHOS_ARCHLIVE_ROOT="$tmp" bash "$HOTFIX" >/tmp/mechos-auto-reboot-validation.log
TEST_INSTALLER="$tmp/usr/local/bin/mechos-install"
bash -n "$TEST_INSTALLER" || fail "generated installer repair produced invalid shell"
grep -Fq 'payload-server-and-hardware-scan-must-survive' "$TEST_INSTALLER" || fail "generated installer repair overwrote earlier installer functionality"
grep -Fq 'trap ' "$TEST_INSTALLER" || fail "generated installer cleanup/trap content was not preserved"
grep -Fq 'MECHOS_INSTALL_SUCCESS_AUTO_REBOOT_V1' "$TEST_INSTALLER" || fail "generated installer did not receive reboot policy"
grep -Fq 'install_rc=$?' "$TEST_INSTALLER" || fail "generated installer does not capture archinstall rc"
grep -Fq 'if [[ "$install_rc" -ne 0 ]]' "$TEST_INSTALLER" || fail "generated installer failure guard missing"
grep -Fq 'systemctl reboot' "$TEST_INSTALLER" || fail "generated installer reboot action missing"
if grep -Fq 'THIS COMPLETION TEXT IS INTENTIONALLY DIFFERENT' "$TEST_INSTALLER"; then
  fail "obsolete generated completion tail survived final repair"
fi

# The final guard must be idempotent on the already-repaired generated backend.
MECHOS_ARCHLIVE_ROOT="$tmp" bash "$HOTFIX" >/tmp/mechos-auto-reboot-validation-idempotent.log
grep -Fq 'success-only reboot policy already installed' /tmp/mechos-auto-reboot-validation-idempotent.log || fail "final reboot guard is not idempotent"

python3 - "$PATCHER" <<'PY'
from pathlib import Path
import sys
text=Path(sys.argv[1]).read_text(encoding='utf-8')
a=text.find('mechos-update-center-v2-integration.sh')
b=text.find('mechos-installer-auto-reboot-hotfix.sh')
c=text.find('mechos-installed-mechscope-launch-hotfix.sh')
if min(a,b,c) < 0 or not (a < b < c):
    raise SystemExit('[validate-installer-auto-reboot] success reboot policy must be final after updater and before installed-session finalization')
PY

echo '[validate-installer-auto-reboot] OK: generated installer completion wording is irrelevant; final Archinstall execution becomes success-only reboot while earlier installer behavior is preserved'
