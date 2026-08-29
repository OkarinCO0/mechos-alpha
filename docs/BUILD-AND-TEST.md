# Building and testing MechOS 0.3

1. Install Fedora 44 KDE on a build machine or VM.
2. Give the build environment at least 50 GB free space; 80 GB is more comfortable.
3. Extract this project.
4. Run `sudo ./scripts/setup-build-host.sh`.
5. Run `./scripts/validate-project.sh`.
6. Run `./build-iso.sh`.
7. Verify `out/MechOS-0.3.2-alpha-x86_64.iso.sha256`.
8. Test the ISO in a VM before writing it to a USB drive.

`./scripts/test-iso-qemu.sh` is provided for an accelerated QEMU smoke test when the host supports KVM and virgl.

## What to test first

- live ISO reaches KDE/installer
- Plymouth artwork appears
- installation completes
- first installed boot creates `/var/lib/mechos/firstboot.done`
- Steam becomes available after network bootstrap
- SDDM autologins into `MechScope`
- a controller can navigate Steam Gamepad UI
- Desktop Mode exits MechScope and starts Plasma Wayland
- Return to Gaming Mode relaunches MechScope
- AMD/Intel Vulkan works, or NVIDIA driver setup completes and survives reboot

## NVIDIA note

The source ISO does not embed proprietary driver packages. `mechos-firstboot` enables RPM Fusion and `mechos-gpu-setup` installs the NVIDIA driver when an NVIDIA GPU is detected. This avoids silently baking third-party proprietary packages into the source tree.
