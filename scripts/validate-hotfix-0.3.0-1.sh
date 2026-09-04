#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT/scripts/mechos-hotfix-0.3.0-1-apply.sh"
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.1-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"
EXPECTED_SHA="7e94b24876e70989f94873b3971f1cf89b781252227fa133a1ac0c92edd2a3d9"
fail(){ echo "[validate-hotfix-0.3.0-1] ERROR: $*" >&2; exit 1; }

[ -f "$HELPER" ] || fail "Hotfix 1 apply helper missing"
bash -n "$HELPER" || fail "Hotfix 1 apply helper shell syntax failed"
grep -Fq 'MECHOS_VM_MODE_RUNTIME_ROUTER_V1' "$HELPER" || fail "VM controller router repair missing"
grep -Fq 'MECHOS_VM_PLASMA_HOST_V2' "$HELPER" || fail "VM MechScope session repair missing"
grep -Fq 'MECHOS_REFERENCE_SPLASH_V1' "$HELPER" || fail "reference Plymouth theme repair missing"
grep -Fq 'mkinitcpio -P' "$HELPER" || fail "initramfs rebuild missing"
grep -Fq 'quiet splash' "$HELPER" || fail "kernel splash options repair missing"
grep -Fq 'hotfix-0.3.0-1-applied' "$HELPER" || fail "one-time completion marker missing"

[ -s "$BUNDLE" ] || fail "published Hotfix 1 bundle missing"
[ -s "$SUM" ] || fail "published Hotfix 1 checksum missing"
actual="$(sha256sum "$BUNDLE" | awk '{print $1}')"
[ "$actual" = "$EXPECTED_SHA" ] || fail "Hotfix 1 bundle SHA mismatch: $actual"
(
  cd "$(dirname "$BUNDLE")"
  sha256sum -c "$(basename "$SUM")"
) >/dev/null || fail "Hotfix 1 checksum file does not verify"

python3 - "$BUNDLE" <<'PY'
from pathlib import PurePosixPath
import subprocess,sys
bundle=sys.argv[1]
p=subprocess.run(['tar','--zstd','-tf',bundle],text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
if p.returncode:
    raise SystemExit('[validate-hotfix-0.3.0-1] unable to list bundle')
allowed=(
 'usr/local/', 'usr/share/mechos/', 'usr/share/applications/',
 'usr/share/wayland-sessions/', 'usr/lib/systemd/', 'etc/mechos/',
 'etc/systemd/', 'etc/xdg/'
)
# tar includes structural parent directories such as `usr/`, `usr/lib/` and
# `etc/`. Accept a directory only when it is a parent of an approved prefix;
# files still must live at or below one of the explicit Update Center paths.
allowed_parents=set()
for prefix in allowed:
    parts=prefix.rstrip('/').split('/')
    for i in range(1,len(parts)):
        allowed_parents.add('/'.join(parts[:i]))
required={
 'usr/local/bin/mechos-vm-mode-runtime',
 'usr/local/libexec/mechos-hotfix-0.3.0-1-apply',
 'usr/lib/systemd/user/mechos-vm-mechscope.service',
 'usr/lib/systemd/user/mechos-vm-creator.service',
 'usr/lib/systemd/system/mechos-hotfix-0.3.0-1.service',
 'etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-1.service',
 'etc/xdg/autostart/mechos-vm-mode-runtime.desktop',
}
seen=set()
for raw in p.stdout.splitlines():
    name=raw.strip()
    while name.startswith('./'): name=name[2:]
    if not name or name=='.': continue
    path=PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts:
        raise SystemExit(f'[validate-hotfix-0.3.0-1] unsafe bundle path: {name}')
    normalized=name.rstrip('/')
    is_dir=name.endswith('/')
    if is_dir and normalized in allowed_parents:
        seen.add(normalized)
        continue
    if not any(normalized==x.rstrip('/') or normalized.startswith(x) for x in allowed):
        raise SystemExit(f'[validate-hotfix-0.3.0-1] path outside Update Center allowlist: {name}')
    seen.add(normalized)
missing=sorted(required-seen)
if missing:
    raise SystemExit('[validate-hotfix-0.3.0-1] bundle missing required files: '+', '.join(missing))
PY

python3 - "$MANIFEST" "$EXPECTED_SHA" <<'PY'
import json,sys
path,expected=sys.argv[1:]
with open(path,encoding='utf-8') as f: data=json.load(f)
if data.get('version') != '0.3.0-hotfix.1':
    raise SystemExit('[validate-hotfix-0.3.0-1] stable manifest version is not Hotfix 1')
if data.get('bundle_sha256') != expected:
    raise SystemExit('[validate-hotfix-0.3.0-1] stable manifest SHA does not match bundle')
if data.get('bundle_url') != 'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.1-update.tar.zst':
    raise SystemExit('[validate-hotfix-0.3.0-1] stable manifest bundle URL is wrong')
if data.get('requires_reboot') is not True:
    raise SystemExit('[validate-hotfix-0.3.0-1] Hotfix 1 must require reboot')
PY

echo '[validate-hotfix-0.3.0-1] OK: Hotfix 1 helper, published bundle, SHA-256, allowlist and stable manifest all verify'
