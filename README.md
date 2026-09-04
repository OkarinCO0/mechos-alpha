# MechOS 0.3.0 Alpha — Arch Gaming and Creator ISO

MechOS is an Arch Linux-based gaming distribution prototype. Its ISO boots to a KDE Plasma live desktop with the MechOS Setup Center, while installed systems default to the MechScope gaming session.

## Live and installation flow

1. Write `MechOS-Arch-Creator-x86_64.iso` to a USB drive or attach it to a virtual machine.
2. Boot the MechOS live image.
3. KDE Plasma opens with the MechOS Setup Center.
4. Choose **Install MechOS** to launch the guided Archinstall interface.
5. Select and confirm the target disk inside Archinstall. The repository intentionally does not preselect or erase a disk.
6. Reboot after installation.
7. First boot validates graphics and services, then MechScope becomes the default gaming session.

The setup center is graphical. Archinstall itself uses a guided terminal interface so disk selection and its final destructive confirmation remain visible.

## Included foundation

- Arch Linux and ArchISO
- KDE Plasma live and desktop sessions
- MechScope with Gamescope and Steam Gamepad UI
- AMD, Intel and NVIDIA graphics packages
- Lutris, Wine, Winetricks, Protontricks, GameMode and MangoHud
- GPU Screen Recorder, OBS Studio and Kdenlive
- Creator Mode package groups for Blender, Krita, game development and Windows applications
- Post-install center, update center, performance center and recovery helpers
- Btrfs/Snapper recovery support when the installed filesystem is compatible
- Nineteen MechOS wallpapers and branded Plymouth assets

No anti-cheat bypass is included. Game compatibility still depends on each game's Linux and anti-cheat support.

## Validate the repository

```bash
./scripts/validate-project.sh
```

This checks active files, shell and Python syntax, Arch-specific metadata, patcher idempotency, workflow wiring and wallpaper integrity without building an ISO.

## Build locally

The supported local build path uses a privileged Arch Linux Docker container:

```bash
./scripts/setup-build-host.sh
./build-iso.sh
```

Allow at least 45 GiB of free space; 70 GiB is recommended. The output is:

```text
out/MechOS-Arch-Creator-x86_64.iso
out/MechOS-Arch-Creator-x86_64.iso.sha256
```

## Build with GitHub Actions

Open **Actions → Build MechOS Arch ISO → Run workflow**. Source validation also runs automatically on pull requests and pushes to `main`.

## Release certification

Before publishing a v0.3.0 build, complete `docs/RELEASE-CERTIFICATION-v0.3.0.md`. It is the GO / NO-GO release gate for ISO integrity, Live boot, clean installation, OOBE, MechScope, Creator Mode, mode switching, physical hardware, Vulkan/GPU behavior, Steam/Proton, updates, recovery, installer safety and release hygiene.

See `CLOUD-BUILD.md`, `docs/BUILD-AND-TEST.md` and `docs/RELEASE-CERTIFICATION-v0.3.0.md` for build and release testing.
