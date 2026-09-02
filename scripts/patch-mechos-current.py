#!/usr/bin/env python3
from __future__ import annotations

import re
import shutil
import sys
from pathlib import Path

MARKER_EARLY = "# MECHOS_CURRENT_INTEGRATION_EARLY"
MARKER_LATE = "# MECHOS_CURRENT_INTEGRATION_LATE"

CALL_EARLY = f"""{MARKER_EARLY}
# Apply the cumulative MechOS runtime/installer integration.
bash /workspace/scripts/mechos-current-integration.sh early

"""

CALL_LATE = f"""{MARKER_LATE}
# Re-apply after all legacy builder blocks so current fixes win.
bash /workspace/scripts/mechos-current-integration.sh final
# Add the guided dual-boot/Install Alongside flow after the graphical installer
# and post-install payload have both been generated.
bash /workspace/scripts/mechos-alongside-integration.sh final
# For whole-disk Clean Install, make the disk chosen in the Live graphical
# selector the only disk that gets erased, partitioned, formatted and installed.
bash /workspace/scripts/mechos-selected-drive-clean-install-integration.sh final
# The location UI reads its JSON target with pathlib.Path. Ensure the final
# generated installer imports Path so target selection cannot fail at runtime.
bash /workspace/scripts/mechos-installer-path-import-hotfix.sh final
# Turn the Live Reinstall/Keep Home path into a real ISO refresh that preserves
# /home, user identity and machine-specific settings without formatting disks.
bash /workspace/scripts/mechos-live-update-keep-home-integration.sh final
# Configure the installed-system MechOS graphical GRUB boot menu before OOBE.
bash /workspace/scripts/mechos-graphical-bootloader-integration.sh final
# Add the post-install owner setup flow before any MechScope first-run UI.
bash /workspace/scripts/mechos-oobe-integration.sh final
# Turn Creator presets into saved workflow profiles that can auto-launch only
# the installed apps needed for the selected Creator workflow.
bash /workspace/scripts/mechos-creator-profile-integration.sh final
# Add first-run navigation tutorials after MechScope/Creator Mode and the
# installed-system payload have been generated.
bash /workspace/scripts/mechos-tutorial-integration.sh final
# Hard-gate tutorial auto-launch to a completed MechOS post-install and OOBE.
bash /workspace/scripts/mechos-tutorial-postinstall-guard.sh final
# Keep heavyweight Creator applications out of the core ISO; Creator Mode can
# install them on demand when the user selects those workflows.
bash /workspace/scripts/mechos-footprint-integration.sh final
# Apply boot-to-MechScope performance fixes after the installed rootfs archive
# exists so FastBoot can patch both the Live image and installed-system payload.
bash /workspace/scripts/mechos-fastboot-integration.sh final
# Normalize MechScope's stylesheet hook after all late integrations so the
# shared visual-theme pass cannot miss a modified setStyleSheet expression.
bash /workspace/scripts/mechos-ui-theme-compat-hotfix.sh final
# Apply the lightweight shared MechOS theme and System Tools Hub.
bash /workspace/scripts/mechos-ui-polish-integration.sh final
# Make the Optimization Report visible and usable from Performance Center and
# System Tools after their final UI versions have been generated.
bash /workspace/scripts/mechos-optimization-report-ui-integration.sh final
# Final installer authority: replace the remaining Clean Install handoff with
# MechOS-owned partitioning, package provisioning, payload deployment and boot.
bash /workspace/scripts/mechos-native-installer-integration.sh final
# Apply small runtime hardening after the native helper has been generated.
bash /workspace/scripts/mechos-native-installer-runtime-hotfix.sh final
# Fix multi-word VM/physical disk model detection and make whole-disk routing
# native-only even if an older selected-target launch hook survives.
bash /workspace/scripts/mechos-live-disk-routing-hotfix.sh final
# Make the custom MechScope shell the one Gaming Mode surface everywhere.
# Store/Downloads stay full-screen and the VM Plasma fallback hides desktop
# chrome while MechScope is active.
bash /workspace/scripts/mechos-mechscope-shell-integration.sh final
# Master colors, focus states, typography and reusable card controls.
bash /workspace/scripts/mechos-reference-ui-integration.sh final
# Rebuild the game Store and Creator Store as full Reference UI v3 surfaces.
bash /workspace/scripts/mechos-reference-stores-v3-integration.sh final
# Keep separately installed RadarAI discoverable from Performance Center.
bash /workspace/scripts/mechos-radarai-performance-integration.sh final
# FINAL INTERACTIVE SURFACE AUTHORITY: rebuild Performance Center, Update Center,
# Quick Actions, Stream Center and Recovery around the approved graphical
# reference, and harden Creator <-> MechScope same-session transitions.
bash /workspace/scripts/mechos-reference-surfaces-v4-integration.sh final
# FINAL LIVE AUTHORITY: no later compatibility block may re-enable SDDM relogin
# loops or route a MechOS installer button back into Archinstall.
bash /workspace/scripts/mechos-live-authority-hotfix.sh final

"""


def fail(message: str) -> None:
    raise SystemExit(f"[MechOS current patcher] ERROR: {message}")


def strip_injected_calls(text: str) -> str:
    """Remove call blocks previously inserted by current/legacy patchers."""
    for marker, command in (
        ("# MECHOS_V0_2_1_REPAIR_EARLY", "bash /workspace/scripts/mechos-v0.2.1-runtime-repair.sh early"),
        ("# MECHOS_V0_2_1_REPAIR_LATE", "bash /workspace/scripts/mechos-v0.2.1-runtime-repair.sh final"),
        ("# MECHOS_V0_2_2_REPAIR_EARLY", "bash /workspace/scripts/mechos-v0.2.2-runtime-repair.sh early"),
        ("# MECHOS_V0_2_2_REPAIR_LATE", "bash /workspace/scripts/mechos-v0.2.2-runtime-repair.sh final"),
    ):
        text = re.sub(
            rf"\n{re.escape(marker)}\n.*?{re.escape(command)}\n\n",
            "\n",
            text,
            flags=re.S,
        )

    text = re.sub(
        rf"\n{re.escape(MARKER_EARLY)}\n.*?bash /workspace/scripts/mechos-current-integration\.sh early\n\n",
        "\n",
        text,
        flags=re.S,
    )

    text = re.sub(
        rf"\n{re.escape(MARKER_LATE)}\n.*?(?=^(?!\s*#).*\bmkarchiso\b.*$)",
        "\n",
        text,
        flags=re.S | re.M,
    )
    return text


def main() -> None:
    target = Path(sys.argv[1] if len(sys.argv) > 1 else "scripts/build-mechos-archiso.sh")
    if not target.is_file():
        fail(f"builder not found: {target}")

    text = target.read_text(encoding="utf-8")
    if not text.startswith("#!"):
        fail("target does not look like a shell builder")

    if (
        text.count(MARKER_EARLY) == 1
        and text.count(MARKER_LATE) == 1
        and "mechos-selected-drive-clean-install-integration.sh final" in text
        and "mechos-installer-path-import-hotfix.sh final" in text
        and "mechos-live-update-keep-home-integration.sh final" in text
        and "mechos-native-installer-integration.sh final" in text
        and "mechos-native-installer-runtime-hotfix.sh final" in text
        and "mechos-live-disk-routing-hotfix.sh final" in text
        and "mechos-mechscope-shell-integration.sh final" in text
        and "mechos-reference-ui-integration.sh final" in text
        and "mechos-reference-stores-v3-integration.sh final" in text
        and "mechos-radarai-performance-integration.sh final" in text
        and "mechos-reference-surfaces-v4-integration.sh final" in text
        and "mechos-live-authority-hotfix.sh final" in text
    ):
        print(f"[MechOS current patcher] current integration already applied to {target}")
        return

    backup = target.with_suffix(target.suffix + ".pre-current-integration.bak")
    if not backup.exists():
        shutil.copy2(target, backup)

    text = strip_injected_calls(text)

    installer_patterns = [
        r'(?m)^cat > /workspace/archlive/airootfs/usr/local/bin/mechos-install << ["\']?EOF["\']?\s*$',
        r'(?m)^cat > .*?/usr/local/bin/mechos-install << ["\']?EOF["\']?\s*$',
    ]
    installer_match = None
    for pattern in installer_patterns:
        installer_match = re.search(pattern, text)
        if installer_match:
            break
    if not installer_match:
        fail("could not locate mechos-install heredoc; refusing a blind patch")

    text = text[:installer_match.start()] + CALL_EARLY + text[installer_match.start():]

    mk_matches = list(re.finditer(r'(?m)^(?!\s*#).*\bmkarchiso\b.*$', text))
    if not mk_matches:
        fail("could not locate mkarchiso; refusing a blind patch")
    mk_match = mk_matches[-1]
    text = text[:mk_match.start()] + CALL_LATE + text[mk_match.start():]

    if text.count(MARKER_EARLY) != 1 or text.count(MARKER_LATE) != 1:
        fail("integration markers are not unique after patching")
    required = (
        "mechos-selected-drive-clean-install-integration.sh final",
        "mechos-installer-path-import-hotfix.sh final",
        "mechos-live-update-keep-home-integration.sh final",
        "mechos-native-installer-integration.sh final",
        "mechos-native-installer-runtime-hotfix.sh final",
        "mechos-live-disk-routing-hotfix.sh final",
        "mechos-mechscope-shell-integration.sh final",
        "mechos-reference-ui-integration.sh final",
        "mechos-reference-stores-v3-integration.sh final",
        "mechos-radarai-performance-integration.sh final",
        "mechos-reference-surfaces-v4-integration.sh final",
        "mechos-live-authority-hotfix.sh final",
    )
    for command in required:
        if command not in text:
            fail(f"required integration was not wired: {command}")

    target.write_text(text, encoding="utf-8")
    print(f"[MechOS current patcher] cumulative integration applied to {target}")


if __name__ == "__main__":
    main()
