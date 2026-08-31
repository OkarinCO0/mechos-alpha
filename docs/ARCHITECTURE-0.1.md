# MechOS architecture

## Base and image pipeline

MechOS 0.3.0 Alpha uses Arch Linux. `scripts/build-mechos-archiso.sh` copies ArchISO's `releng` profile, adds the MechOS package list and root filesystem, applies the cumulative integration, and runs `mkarchiso`.

## Sessions

- **MechOS Gaming** starts MechScope, Gamescope and Steam Gamepad UI.
- **Desktop** starts KDE Plasma Wayland.
- **Creator Mode** exposes creator application groups and project shortcuts on installed systems.

The live ISO always starts Plasma so installation and recovery remain accessible. Installed systems use the real Archinstall-created user and default to MechOS Gaming.

## Graphics

- AMD: Mesa, RADV and 32-bit Vulkan packages.
- Intel: Mesa, Intel Vulkan and media-driver packages.
- NVIDIA: `nvidia-open`, NVIDIA utilities and PRIME helpers for supported hardware.

MechScope falls back to Plasma when Steam or Gamescope is unavailable. HDR remains opt-in because capability varies by display and driver.

## Installation

The graphical live Setup Center starts Archinstall with a partial configuration. It supplies MechOS post-install commands but deliberately leaves disk layout, formatting and final confirmation to the user.

The installed-system payload is staged separately from live-only setup files. Post-install validation checks that required MechOS and Plasma components survived installation.

## Updates and recovery

The update helper uses Pacman and Flatpak. Btrfs installations can use Snapper checkpoints and the recovery tools can collect diagnostics, repair boot configuration and guide rollback.
