# MechOS 0.3.2 Alpha — Graphical Installer ISO Builder

MechOS 0.3.2 changes the end-user installation flow so **installing MechOS requires no terminal commands**.

## End-user flow

1. Write the compiled MechOS ISO to a USB drive using a graphical USB writer.
2. Boot the PC from the MechOS USB.
3. The live environment opens **Welcome to MechOS** automatically.
4. Choose **Install MechOS to this computer**.
5. The Fedora 44 Anaconda WebUI installer handles language, keyboard, time zone, user account, and storage graphically.
6. Reboot when installation is finished.
7. The installed system performs MechOS first-boot GPU/gaming setup automatically and then uses **MechScope** as its normal gaming session.

No shell commands are part of the user installation path.

## Live USB choices

The graphical welcome screen provides:

- **Install MechOS** — opens the graphical Anaconda WebUI installer.
- **Try MechOS Desktop Mode** — stays in KDE Plasma.
- **Start MechScope Gaming Mode** — switches the live session to Gamescope + Steam Gamepad UI when Steam is available.
- **Shut Down**.

An **Install MechOS** icon is also placed on the live desktop.

## Installed boot flow

```text
Power on
  -> MechOS Plymouth boot intro
  -> SDDM autologin
  -> MechScope
  -> Gamescope
  -> Steam Gamepad / SteamOS-style UI
```

Desktop Mode remains available through the MechOS/Steam session switch.

## Included foundation

- Fedora 44 KDE live/installable base
- Anaconda live installer + Anaconda WebUI
- MechOS installer branding layer
- MechScope Gamescope session
- Steam Gamepad UI bootstrap
- KDE Plasma Desktop Mode
- Lutris, GameMode, MangoHud and Vulkan utilities
- AMD/Intel Mesa stack
- NVIDIA detection and RPM Fusion driver bootstrap after install
- 19 MechOS mech-themed wallpapers
- Plymouth/MechScope artwork
- Btrfs/Snapper recovery helper
- Unity Hub, Blender and OBS creator setup
- Unreal Engine, VRChat tooling and MechClip integration hooks

## Building the ISO (developer/release step)

The **release builder** still has to compile the ISO on Fedora 44. These commands are for the person producing MechOS releases, not for someone installing MechOS:

```bash
sudo ./scripts/setup-build-host.sh
./scripts/validate-project.sh
./build-iso.sh
```

Output:

```text
out/MechOS-0.3.2-alpha-x86_64.iso
out/MechOS-0.3.2-alpha-x86_64.iso.sha256
```

## Important alpha notes

- This package is the complete ISO **builder project**, not a precompiled multi-gigabyte Fedora ISO.
- Steam and proprietary NVIDIA drivers are bootstrapped from RPM Fusion after installation when networking is available; they are not bundled illegally.
- Unreal Engine, proprietary Unity Editor versions, and Windows-only VRChat Creator Companion are not redistributed in this source bundle.
- No anti-cheat bypass is included.

## Cloud ISO build (0.3.2 packaging revision)

This package also includes `.github/workflows/build-mechos-iso.yml` so the ISO can be compiled in GitHub Actions without installing Fedora on your own PC. See `CLOUD-BUILD.md`.
