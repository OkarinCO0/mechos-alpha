#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLY="$ROOT/scripts/mechos-hotfix-0.3.0-2-apply.sh"
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.2-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
fail(){ echo "[validate-hotfix-0.3.0-2] ERROR: $*" >&2; exit 1; }

[ -f "$APPLY" ] || fail "Hotfix 2 apply helper missing"
bash -n "$APPLY" || fail "Hotfix 2 apply helper shell syntax failed"
grep -Fq 'mechos-oobe-start' "$APPLY" || fail "automatic account creation launcher missing"
grep -Fq 'User=mechos-setup' "$APPLY" || fail "temporary setup account handoff missing"
grep -Fq 'Exec=/usr/local/bin/mechos-mode-launch gaming' "$APPLY" || fail "Return to MechScope desktop launcher repair missing"
grep -Fq 'Exec=/usr/local/bin/mechos-mode-launch creator' "$APPLY" || fail "Creator desktop launcher repair missing"
grep -Fq 'systemd-detect-virt' "$APPLY" || fail "VM/physical launcher routing missing"
grep -Fq 'MECHOS_CREATOR_REFERENCE_NATIVE_SCALE_V1' "$APPLY" || fail "Creator alignment repair missing"

[ -s "$BUNDLE" ] || fail "Hotfix 2 bundle missing"
[ -s "$SUM" ] || fail "Hotfix 2 checksum missing"
(
  cd "$(dirname "$BUNDLE")"
  sha256sum -c "$(basename "$SUM")"
) >/dev/null || fail "Hotfix 2 checksum file does not verify"
SHA="$(sha256sum "$BUNDLE" | awk '{print $1}')"

python3 - "$BUNDLE" <<'PY'
from pathlib import PurePosixPath
import subprocess,sys
bundle=sys.argv[1]
p=subprocess.run(['tar','--zstd','-tf',bundle],text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
if p.returncode: raise SystemExit('unable to list Hotfix 2 bundle')
allowed=(
 'usr/local/', 'usr/share/mechos/', 'usr/share/applications/',
 'usr/share/wayland-sessions/', 'usr/lib/systemd/', 'etc/mechos/',
 'etc/systemd/', 'etc/xdg/'
)
allowed_parents=set()
for prefix in allowed:
    parts=prefix.rstrip('/').split('/')
    for i in range(1,len(parts)): allowed_parents.add('/'.join(parts[:i]))
required={
 'usr/local/bin/mechos-oobe',
 'usr/local/libexec/mechos-oobe-apply',
 'usr/local/libexec/mechos-oobe-cleanup',
 'usr/local/libexec/mechos-hotfix-0.3.0-2-apply',
 'usr/lib/systemd/system/mechos-hotfix-0.3.0-2.service',
 'etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-2.service',
}
seen=set()
for raw in p.stdout.splitlines():
    name=raw.strip()
    while name.startswith('./'): name=name[2:]
    if not name or name=='.': continue
    path=PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts: raise SystemExit(f'unsafe bundle path: {name}')
    normalized=name.rstrip('/'); is_dir=name.endswith('/')
    if is_dir and normalized in allowed_parents:
        seen.add(normalized); continue
    if not any(normalized==x.rstrip('/') or normalized.startswith(x) for x in allowed):
        raise SystemExit(f'path outside Update Center allowlist: {name}')
    seen.add(normalized)
missing=sorted(required-seen)
if missing: raise SystemExit('bundle missing required files: '+', '.join(missing))
PY

python3 - "$MANIFEST" "$SHA" <<'PY'
import json,sys
with open(sys.argv[1],encoding='utf-8') as f: data=json.load(f)
if data.get('version') != '0.3.0-hotfix.2': raise SystemExit('stable manifest is not Hotfix 2')
if data.get('bundle_sha256') != sys.argv[2]: raise SystemExit('manifest SHA does not match bundle')
if data.get('bundle_url') != 'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.2-update.tar.zst': raise SystemExit('Hotfix 2 URL is wrong')
if data.get('requires_reboot') is not True: raise SystemExit('Hotfix 2 must require reboot')
PY

echo '[validate-hotfix-0.3.0-2] OK: OOBE trigger, universal desktop launchers, Creator alignment, bundle and manifest verify'
