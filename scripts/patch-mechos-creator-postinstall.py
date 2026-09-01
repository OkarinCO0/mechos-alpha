#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path

MARKER = "# MECHOS_CREATOR_POSTINSTALL_INTEGRATION"
CALL = MARKER + """
# Keep Creator applications out of the base image and offer them as an
# opt-in step after account setup, before MechScope starts.
# Creator Mode itself is post-install-only after the footprint pass. Adapt the
# older Creator postinstall integration to the persistent Plasma gaming layer.
python3 - <<'PY'
from pathlib import Path

path = Path('/workspace/scripts/mechos-creator-postinstall-integration.sh')
text = path.read_text(encoding='utf-8')
lines = text.splitlines()

# Creator Mode is intentionally absent from the Live tree after the footprint
# pass, but it must still be present and patched in the installed payload.
old_creator = '  [ -f "$creator" ] || fail "Creator Mode executable is missing in $tree"'
if old_creator in lines:
    i = lines.index(old_creator)
    lines[i:i + 1] = [
        '  if [ ! -f "$creator" ]; then',
        '    log "Creator Mode is post-install-only in $tree; keeping category manifests and post-install runtime without patching a Live Creator executable"',
        '    return 0',
        '  fi',
    ]
elif not any('Creator Mode is post-install-only in $tree' in line for line in lines):
    raise SystemExit('Creator post-install compatibility point was not found; refusing a blind patch')

# The old postinstall runner tried to launch a removed mechos-gaming-shell.
# Start the new persistent-Plasma gaming layer instead.
for i in range(len(lines) - 2):
    if (
        lines[i] == 'if [ -x /usr/local/bin/mechos-gaming-shell ]; then'
        and lines[i + 1] == '  nohup /usr/local/bin/mechos-gaming-shell >/dev/null 2>&1 &'
        and lines[i + 2] == 'fi'
    ):
        lines[i:i + 3] = [
            'if [ -x /usr/local/bin/mechos-gaming-layer-control ]; then',
            '  nohup /usr/local/bin/mechos-gaming-layer-control start >/dev/null 2>&1 &',
            'fi',
        ]
        break

for i, line in enumerate(lines):
    if line == '        if Path("/usr/local/bin/mechos-gaming-shell").exists():':
        lines[i] = '        if Path("/usr/local/bin/mechos-gaming-layer-control").exists():'
    elif line == '                ["/usr/local/bin/mechos-gaming-shell"],':
        lines[i] = '                ["/usr/local/bin/mechos-gaming-layer-control", "start"],'

# Gate the actual gaming-layer autostart until the Creator Apps setup has been
# completed or explicitly skipped. The previous code targeted a deleted shell.
old_gate_start = '  local gaming="$bin/mechos-gaming-shell"'
if old_gate_start in lines:
    start = lines.index(old_gate_start)
    end = None
    for j in range(start, len(lines)):
        if lines[j] == '    bash -n "$gaming" || fail "gaming shell syntax failed after Creator postinstall gate"':
            if j + 1 < len(lines) and lines[j + 1] == '  fi':
                end = j + 2
            break
    if end is None:
        raise SystemExit('Old Creator gaming-shell gate block was not complete; refusing a blind patch')
    replacement = [
        '  local gaming_autostart="$bin/mechos-gaming-layer-autostart"',
        '  if [ -f "$gaming_autostart" ] && ! grep -Fq MECHOS_CREATOR_POSTINSTALL_GATE "$gaming_autostart"; then',
        '    tmp_gate="$(mktemp)"',
        '    {',
        '      head -n1 "$gaming_autostart"',
        "      cat <<'GATE_EOF'",
        '# MECHOS_CREATOR_POSTINSTALL_GATE',
        'if [ -e /var/lib/mechos/oobe-complete ] && [ ! -e "${XDG_CONFIG_HOME:-$HOME/.config}/mechos/creator-postinstall-complete" ]; then',
        '  exit 0',
        'fi',
        'GATE_EOF',
        '      tail -n +2 "$gaming_autostart"',
        '    } > "$tmp_gate"',
        '    cat "$tmp_gate" > "$gaming_autostart"',
        '    rm -f "$tmp_gate"',
        '    chmod 755 "$gaming_autostart"',
        '    bash -n "$gaming_autostart" || fail "gaming-layer autostart syntax failed after Creator postinstall gate"',
        '  fi',
    ]
    lines[start:end] = replacement
elif not any('local gaming_autostart="$bin/mechos-gaming-layer-autostart"' in line for line in lines):
    raise SystemExit('Creator gaming-layer gate compatibility point was not found; refusing a blind patch')

# Replace the old final validation semantically instead of depending on whether
# the source happens to quote the grep marker with single or double quotes.
new_check = 'grep -Fq MECHOS_CREATOR_POSTINSTALL_GATE "$ROOT/usr/local/bin/mechos-gaming-layer-autostart" || fail "MechScope gaming-layer startup gate is missing"'
replaced_check = False
for i, line in enumerate(lines):
    if (
        line.startswith('grep -Fq ')
        and 'MECHOS_CREATOR_POSTINSTALL_GATE' in line
        and 'mechos-gaming-shell' in line
        and 'startup gate is missing' in line
    ):
        lines[i] = new_check
        replaced_check = True
        break
if not replaced_check and new_check not in lines:
    raise SystemExit('Creator postinstall final gate validation point was not found')

path.write_text(chr(10).join(lines) + chr(10), encoding='utf-8')
PY
bash /workspace/scripts/mechos-creator-postinstall-integration.sh final

"""

def fail(message: str) -> None:
    raise SystemExit(f"[MechOS Creator postinstall patcher] ERROR: {message}")

def main() -> None:
    target = Path(sys.argv[1] if len(sys.argv) > 1 else "scripts/build-mechos-archiso.sh")
    if not target.is_file():
        fail(f"builder not found: {target}")

    text = target.read_text(encoding="utf-8")
    if not text.startswith("#!"):
        fail("target does not look like a shell builder")

    text = re.sub(
        rf"\n{re.escape(MARKER)}\n.*?"
        r"bash /workspace/scripts/mechos-creator-postinstall-integration\.sh final\n\n",
        "\n",
        text,
        flags=re.S,
    )

    mk_matches = list(re.finditer(r"(?m)^(?!\s*#).*\bmkarchiso\b.*$", text))
    if not mk_matches:
        fail("could not locate mkarchiso; refusing a blind patch")

    match = mk_matches[-1]
    text = text[: match.start()] + CALL + text[match.start() :]
    target.write_text(text, encoding="utf-8")

    if text.count(MARKER) != 1:
        fail("Creator postinstall marker count is not exactly one")

    print(f"[MechOS Creator postinstall patcher] optional Creator setup added to {target}")

if __name__ == "__main__":
    main()
