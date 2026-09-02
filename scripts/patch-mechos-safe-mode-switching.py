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
# Creator Mode must leave the gaming-layer cgroup before that layer shuts down.
# Run it as an independent user service so the handoff cannot kill the UI.
bash /workspace/scripts/mechos-creator-mode-launch-hotfix.sh final
# Retry nested Gamescope with an alternate backend and detect instant startup
# failures before falling back to the persistent Plasma desktop.
bash /workspace/scripts/mechos-gamescope-amd-compat-integration.sh final
# The Desktop -> MechScope launcher is a normal user-session action. It must not
# use loginctl, sudo, pkexec, or anything else that can request a password.
bash /workspace/scripts/mechos-passwordless-return-integration.sh final
# Installed systems authenticate after boot and resume, but never for mode switches.
bash /workspace/scripts/mechos-postinstall-auth-policy-integration.sh final
# Creator Mode is wrapped by the first-run tutorial. Teach the Discord
# integration to patch mechos-creator-mode.real instead of compiling the Bash wrapper.
python3 /workspace/scripts/patch-mechos-discord-creator-wrapper.py \
  /workspace/scripts/mechos-discord-screenshare-integration.sh
# Discord uses the same user-session PipeWire/portal path in MechScope, Desktop
# and Creator Mode so screen sharing does not require switching sessions.
bash /workspace/scripts/mechos-discord-screenshare-integration.sh final

"""


def fail(message: str) -> None:
    raise SystemExit(f"[MechOS mode-switch patcher] ERROR: {message}")


def strip_existing_block(text: str) -> str:
    """Remove only this patcher's block, preserving other integration blocks."""
    # Integration patchers all insert immediately before mkarchiso and use an
    # all-caps MECHOS_* marker. Stop at the next integration marker or at the
    # actual mkarchiso command. Keep the mkarchiso branch single-line even
    # though the overall expression is DOTALL, otherwise an earlier bash line
    # can accidentally satisfy the boundary by spanning forward to mkarchiso.
    pattern = re.compile(
        rf"\n{re.escape(MARKER)}\n.*?(?="
        rf"^# MECHOS_[A-Z0-9_]+(?:_INTEGRATION)?\s*$|"
        rf"^(?!\s*#)[^\n]*\bmkarchiso\b[^\n]*$)",
        flags=re.S | re.M,
    )
    return pattern.sub("\n", text)


def main() -> None:
    target = Path(sys.argv[1] if len(sys.argv) > 1 else "scripts/build-mechos-archiso.sh")
    if not target.is_file():
        fail(f"builder not found: {target}")

    text = target.read_text(encoding="utf-8")
    if not text.startswith("#!"):
        fail("target does not look like a shell builder")

    text = strip_existing_block(text)

    mk_matches = list(re.finditer(r"(?m)^(?!\s*#)[^\n]*\bmkarchiso\b[^\n]*$", text))
    if not mk_matches:
        fail("could not locate mkarchiso; refusing a blind patch")

    match = mk_matches[-1]
    text = text[: match.start()] + CALL + text[match.start() :]
    target.write_text(text, encoding="utf-8")

    if text.count(MARKER) != 1:
        fail("safe mode-switch marker count is not exactly one")
    hotfix_count = text.count("mechos-creator-mode-launch-hotfix.sh final")
    if hotfix_count != 1:
        fail(f"Creator Mode launch hotfix count is {hotfix_count}, expected 1")

    print(
        f"[MechOS mode-switch patcher] safe in-session switching, Creator Mode service handoff, "
        f"Gamescope compatibility, passwordless mode switching, installed authentication policy "
        f"and Discord screen sharing added to {target}"
    )


if __name__ == "__main__":
    main()
