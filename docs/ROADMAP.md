# MechOS roadmap

## 0.3.0 Alpha — current

- Arch Linux and ArchISO build pipeline
- KDE Plasma live desktop
- MechOS graphical Setup Center with guided Archinstall handoff
- MechScope gaming session and Plasma fallback
- Steam, Gamescope, Lutris, Wine and Proton utilities
- AMD, Intel and NVIDIA package paths
- Creator Mode package groups and one-click installers
- Post-install, update, performance and recovery centers
- Live-versus-installed runtime separation
- Automated static validation on pull requests and `main`

## 0.3.1 — planned

- MechScope Downloads button in the main top-right status area
- compact SteamOS-style Downloads dropdown that opens on the MechScope main page
- scrollable download queue with a fixed header/footer
- MechOS neon-styled progress bars with download percentage, speed, size, ETA and install state
- queued, downloading, installing, paused, completed and failed/retry states
- controller, keyboard, mouse and touch navigation for the Downloads dropdown
- shortcut to Steam Downloads while keeping Steam game downloads controlled by Steam
- MechOS-managed Creator Mode, Flatpak and system-update jobs shown in the unified Downloads UI when supported
- MechScope Settings > System Update section with a prominent **Check for Updates / Update MechOS** button
- update badge/notification in MechScope when a MechOS update or hotfix is available
- signed MechOS hotfix channel for small reviewed fixes such as `0.3.0-HF1`, `HF2`, etc.
- normal MechOS release update channel for upgrades such as `0.3.0 -> 0.3.1`
- pre-update Snapper snapshot and rollback protection before MechOS hotfix/update installation when supported
- update history, release notes, reboot-required state and failed-update recovery surfaced through the MechOS Update Center
- USB4 and Thunderbolt-class device support using the Linux kernel and userspace authorization stack supported by the detected hardware
- MechScope/Settings USB4 device status for docks, storage, displays, networking and compatible external PCIe/eGPU devices
- USB4 hot-plug detection, connection/authorization status, reconnect handling and hardware diagnostics without promising support for devices unsupported by the Linux kernel or vendor firmware
- controller layout manager inside MechScope Settings with built-in Xbox, PlayStation, Nintendo/Switch Pro, Steam Controller/Steam Input and generic SDL-compatible layouts
- per-controller layout profiles with button remapping, stick inversion, deadzones, trigger ranges, sensitivity, controller order and profile save/restore
- advanced controller support for USB and Bluetooth pairing, battery state, calibration, input testing and disconnect/reconnect handling
- advanced mappings for supported gyro, touchpad, rear paddles/extra buttons, rumble/haptics and controller shortcut chords while falling back cleanly when hardware features are unavailable
- separate Desktop and MechScope controller profiles plus optional per-game layout handoff through Steam Input where Steam manages the title
- controller-first navigation and an on-screen controller test/calibration page so every mapped input can be verified before launching a game

## 0.3.x stabilization

- complete clean-VM install test matrix
- controller-first setup and Bluetooth pairing
- multi-GPU and older-NVIDIA compatibility handling
- clearer installer progress and failure recovery
- reduce ISO size and split optional creator packages
- signed release checksums

## 0.4

- MechClip service and capture integration
- VRChat creator workflow helpers
- Unreal Engine authorized installer helper
- MechScope store/library aggregation improvements
- RadarAI issue-reporting integration with reviewable pull requests

## 1.0 goals

- reproducible and signed image pipeline
- stable update channels and rollback UI
- automated AMD, Intel and NVIDIA hardware testing
- polished gamepad-only setup
- stable MechScope boot and desktop switching
