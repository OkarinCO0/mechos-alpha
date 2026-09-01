#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path

MARKER = "# MECHOS_DEFAULT_WALLPAPER_INTEGRATION"
CALL = f"""{MARKER}
# Apply the branded MechOS Plasma wallpaper to Live and installed systems on
# first login without overwriting later user wallpaper choices.
bash /workspace/scripts/mechos-default-wallpaper-integration.sh final
# Normalize the complete bundled wallpaper set to exact 1920x1080 desktop
# images while preserving artwork aspect ratio with a center-cropped cover fit.
bash /workspace/scripts/mechos-wallpaper-resolution-integration.sh final

"""


def fail(message: str) -> None:
    raise SystemExit(f"[MechOS wallpaper patcher] ERROR: {message}")


def main() -> None:
    target = Path(sys.argv[1] if len(sys.argv) > 1 else "scripts/build-mechos-archiso.sh")
    if not target.is_file():
        fail(f"builder not found: {target}")

    text = target.read_text(encoding="utf-8")
    if not text.startswith("#!"):
        fail("target does not look like a shell builder")

    text = re.sub(
        rf"\n{re.escape(MARKER)}\n"
        r"# Apply the branded MechOS Plasma wallpaper to Live and installed systems on\n"
        r"# first login without overwriting later user wallpaper choices\.\n"
        r"bash /workspace/scripts/mechos-default-wallpaper-integration\.sh final\n"
        r"(?:# Normalize the complete bundled wallpaper set to exact 1920x1080 desktop\n"
        r"# images while preserving artwork aspect ratio with a center-cropped cover fit\.\n"
        r"bash /workspace/scripts/mechos-wallpaper-resolution-integration\.sh final\n)?\n",
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
        fail("default wallpaper marker count is not exactly one")
    if text.count("mechos-wallpaper-resolution-integration.sh final") != 1:
        fail("wallpaper resolution integration count is not exactly one")

    print(f"[MechOS wallpaper patcher] default wallpaper + 1920x1080 normalization added to {target}")


if __name__ == "__main__":
    main()
