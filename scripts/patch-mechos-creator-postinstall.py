#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path

MARKER = "# MECHOS_CREATOR_POSTINSTALL_INTEGRATION"
CALL = MARKER + """
# Keep Creator applications out of the base image and offer them as an
# opt-in step after account setup, before MechScope starts.
# Creator Mode itself is post-install-only after the footprint pass, so make
# the Creator post-install integration tolerate the intentionally absent Live
# executable while still requiring and patching the installed payload copy.
python3 - <<'PY'
from pathlib import Path

path = Path('/workspace/scripts/mechos-creator-postinstall-integration.sh')
lines = path.read_text(encoding='utf-8').splitlines()
needle = '  [ -f "$creator" ] || fail "Creator Mode executable is missing in $tree"'
replacement = [
    '  if [ ! -f "$creator" ]; then',
    '    log "Creator Mode is post-install-only in $tree; keeping category manifests and post-install runtime without patching a Live Creator executable"',
    '    return 0',
    '  fi',
]
if needle in lines:
    index = lines.index(needle)
    lines[index:index + 1] = replacement
elif not any('Creator Mode is post-install-only in $tree' in line for line in lines):
    raise SystemExit('Creator post-install compatibility point was not found; refusing a blind patch')
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
