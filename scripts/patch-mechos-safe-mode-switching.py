#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path

MARKER = "# MECHOS_SAFE_MODE_SWITCHING_INTEGRATION"
CALL = f"""{MARKER}
# Keep Plasma as the persistent graphical session and run MechScope/Gamescope
# as a reversible fullscreen layer instead of replacing the login session.
bash /workspace/scripts/mechos-safe-mode-switching-integration.sh final

"""


def fail(message: str) -> None:
    raise SystemExit(f"[MechOS mode-switch patcher] ERROR: {message}")


def main() -> None:
    target = Path(sys.argv[1] if len(sys.argv) > 1 else "scripts/build-mechos-archiso.sh")
    if not target.is_file():
        fail(f"builder not found: {target}")

    text = target.read_text(encoding="utf-8")
    if not text.startswith("#!"):
        fail("target does not look like a shell builder")

    # Idempotent: remove the exact previously injected call block first.
    text = re.sub(
        rf"\n{re.escape(MARKER)}\n"
        r"# Keep Plasma as the persistent graphical session and run MechScope/Gamescope\n"
        r"# as a reversible fullscreen layer instead of replacing the login session\.\n"
        r"bash /workspace/scripts/mechos-safe-mode-switching-integration\.sh final\n\n",
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
        fail("safe mode-switch marker count is not exactly one")

    print(f"[MechOS mode-switch patcher] safe in-session switching added to {target}")


if __name__ == "__main__":
    main()
