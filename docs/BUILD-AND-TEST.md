# Building and testing MechOS 0.3.0 Alpha

## Local build

1. Use a Linux host with Docker and at least 45 GiB free; 70 GiB is recommended.
2. Run `./scripts/setup-build-host.sh`.
3. Run `./scripts/validate-project.sh`.
4. Run `./build-iso.sh`.
5. Verify `out/MechOS-Arch-Creator-x86_64.iso.sha256`.
6. Test the ISO in a virtual machine before writing it to a USB drive.

The Docker build uses `archlinux:latest`, installs ArchISO, stages the MechOS overlay and runs `mkarchiso`.

## Virtual-machine smoke test

`./scripts/test-iso-qemu.sh` starts the ISO with QEMU when QEMU is installed. Test on a virtual disk that contains no important data.

Verify:

- the live ISO reaches KDE Plasma;
- the MechOS Setup Center opens once;
- closing Setup Center leaves a usable desktop;
- Archinstall starts and does not preselect a disk;
- installation completes on a blank virtual disk;
- the installed system does not retain the live `mechos` account configuration;
- SDDM starts and the installed user is selected;
- MechScope falls back to Plasma if Steam or Gamescope is unavailable;
- Desktop, Creator and Gaming mode switching works;
- update, recovery, performance and post-install tools open;
- AMD/Intel Vulkan works, or NVIDIA setup completes without blocking first boot;
- the generated ISO matches its SHA-256 file.

Static validation catches source and configuration mistakes, but only a VM installation can validate partitioning, bootloader, display-manager and graphics behavior.
