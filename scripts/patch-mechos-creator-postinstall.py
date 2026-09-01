#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path

MARKER = "# MECHOS_CREATOR_POSTINSTALL_INTEGRATION"
CALL = f"""{MARKER}
# Keep Creator applications out of the base image and offer them as an
# opt-in step after account setup, before MechScope starts.
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
        rf"\n{re.escape(MARKER)}\n"
        r"# Keep Creator applications out of the base image and offer them as an\n"
        r"# opt-in step after account setup, before MechScope starts\.\n"
        r"bash /workspace/scripts/mechos-creator-postinstall-integration\.sh final\n\n",
        "\n",
        text,
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
