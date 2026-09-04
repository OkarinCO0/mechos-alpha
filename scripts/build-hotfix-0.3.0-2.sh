#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$ROOT/updates/bundles/MechOS-0.3.0-hotfix.2-update.tar.zst"
SUM="$BUNDLE.sha256"
MANIFEST="$ROOT/updates/stable.json"

mkdir -p \
  "$STAGE/usr/local/bin" \
  "$STAGE/usr/local/libexec" \
  "$STAGE/usr/lib/systemd/system" \
  "$STAGE/etc/systemd/system/multi-user.target.wants" \
  "$(dirname "$BUNDLE")"

install -m 0755 "$ROOT/scripts/mechos-hotfix-0.3.0-2-apply.sh" \
  "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-2-apply"

# Hotfix 2 must be able to repair a machine where OOBE never made it into the
# installed payload. Extract the canonical runtime files from the OOBE source
# integration so the update carries them independently of the original ISO.
python3 - "$ROOT/scripts/mechos-oobe-integration.sh" "$STAGE" <<'PY'
from pathlib import Path
import re,sys
src=Path(sys.argv[1]).read_text(encoding='utf-8')
stage=Path(sys.argv[2])

def grab(start, end, out):
    i=src.find(start)
    if i < 0: raise SystemExit(f'missing OOBE source marker: {start}')
    i += len(start)
    j=src.find(end,i)
    if j < 0: raise SystemExit(f'missing OOBE end marker for {out}')
    p=stage/out
    p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text(src[i:j].lstrip('\n'),encoding='utf-8')
    p.chmod(0o755)

grab("cat > \"$bin/mechos-oobe\" <<'PYEOF'", "\nPYEOF", Path('usr/local/bin/mechos-oobe'))
grab("cat > \"$libexec/mechos-oobe-apply\" <<'PYEOF'", "\nPYEOF", Path('usr/local/libexec/mechos-oobe-apply'))
grab("cat > \"$libexec/mechos-oobe-cleanup\" <<'EOF'", "\nEOF", Path('usr/local/libexec/mechos-oobe-cleanup'))
PY

cat > "$STAGE/usr/lib/systemd/system/mechos-hotfix-0.3.0-2.service" <<'EOF'
[Unit]
Description=Apply MechOS v0.3.0 Hotfix 2 runtime repairs
After=local-fs.target
Before=sddm.service display-manager.service
ConditionPathExists=/var/lib/mechos/installed
ConditionPathExists=!/var/lib/mechos/hotfix-0.3.0-2-applied

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/mechos-hotfix-0.3.0-2-apply

[Install]
WantedBy=multi-user.target
EOF
ln -s /usr/lib/systemd/system/mechos-hotfix-0.3.0-2.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/mechos-hotfix-0.3.0-2.service"

bash -n "$STAGE/usr/local/libexec/mechos-hotfix-0.3.0-2-apply"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$STAGE/usr/local/bin/mechos-oobe"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$STAGE/usr/local/libexec/mechos-oobe-apply"
bash -n "$STAGE/usr/local/libexec/mechos-oobe-cleanup"

rm -f "$BUNDLE" "$SUM"
tar --zstd -cpf "$BUNDLE" -C "$STAGE" .
SHA="$(sha256sum "$BUNDLE" | awk '{print $1}')"
printf '%s  %s\n' "$SHA" "$(basename "$BUNDLE")" > "$SUM"

python3 - "$MANIFEST" "$SHA" <<'PY'
from pathlib import Path
import json,sys,datetime
p=Path(sys.argv[1]); sha=sys.argv[2]
data={
  'schema':1,
  'channel':'stable',
  'version':'0.3.0-hotfix.2',
  'release_name':'MechOS v0.3.0 Hotfix 2',
  'published_at':datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
  'notes':'Fixes first-boot account creation so incomplete installs automatically enter MechOS setup after the required reboot; repairs the Creator Mode and Return to MechScope desktop launchers on both virtual machines and physical hardware; and fixes Creator Mode reference UI hit-zone/alignment scaling.',
  'bundle_url':'https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/bundles/MechOS-0.3.0-hotfix.2-update.tar.zst',
  'bundle_sha256':sha,
  'requires_reboot':True,
}
p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY

printf 'Hotfix 2 bundle: %s\nSHA256: %s\n' "$BUNDLE" "$SHA"
