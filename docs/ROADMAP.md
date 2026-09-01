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

### MechScope boot experience

- dedicated animated MechScope startup splash after the normal MechOS system boot screen and before the MechScope home page
- centered MechOS/MechScope emblem and **MECHSCOPE** branding with the existing dark blue/purple neon visual language
- blue-to-purple loading/progress line designed to match the MechOS UI theme
- short startup status messages such as **Loading Gaming Services**, **Starting Gamescope**, **Controller Ready**, **Network Ready** and **Launching MechScope** when those states can be detected reliably
- keep the persistent Plasma session hidden behind the gaming layer so startup feels like a dedicated console rather than exposing a desktop handoff
- smooth transition from the startup splash directly into the MechScope home screen
- retain Gamescope startup with direct-fullscreen MechScope fallback when Gamescope fails so the visual boot experience cannot leave the user stuck on the splash
- keep startup lightweight with no heavy looping video requirement; use efficient animation/static assets so boot performance remains the priority
- allow the splash to surface a clear recovery/fallback message when MechScope or Gamescope cannot start instead of silently hanging

### MechScope downloads and updates

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

### Creator Mode and Windows creator tools

- expand the Creator Mode Store with verified Windows-only creator applications that are usable on MechOS through supported Wine, Bottles, Lutris or Proton-based compatibility paths where appropriate
- keep large creator applications post-install instead of embedding them into the base ISO so users only download the tools they want
- provide packaged per-app install scripts/helpers, dependency setup, status detection, launch entries and uninstall/reinstall paths for Creator Store applications
- preserve and improve the Unity Hub / Unity editor setup workflow instead of bundling Unity editors into the ISO
- preserve the Unreal Engine vendor/Linux setup workflow instead of bundling Unreal Engine into the ISO
- preserve the VRChat Creator Companion Windows compatibility workflow using Wine/Lutris-compatible tooling when supported
- keep Creator Store access to VS Code, GitKraken, Bottles, Heroic, ProtonUp-Qt, Wine, Winetricks and Protontricks alongside native creator tools
- keep Creator profiles for **VRChat Creator**, **Game Dev**, **3D Artist**, **Streaming** and **Manual**, launching installed tools and clearly reporting missing tools that can be installed from the store
- expand the Creator Mode Store with additional game engines, including Windows-only engines only after they are verified to run acceptably on MechOS
- package game-engine install scripts/helpers with required runtimes, launch entries, compatibility notes and version-specific setup instead of relying on undocumented manual installs
- add the new creator tools and game engines to the Creator Mode Store page with categories, install/status buttons, compatibility badges and clear native/Flatpak/vendor/Windows-compatibility labels

### Windows game compatibility and Store verification

- research Windows-only games outside the current MechScope store before listing them as compatible, including install path, launcher behavior, Proton/Wine version, graphics/runtime dependencies and known limitations
- add verified compatible Windows games and their install/compatibility profiles to the MechScope store page rather than presenting untested titles as supported
- provide per-game Linux compatibility setup scripts/helpers for verified Windows-only games, including required legitimate runtimes, launch options, prefixes and Proton/Wine selection where testing shows they are needed
- add compatibility status labels such as **Verified**, **Playable**, **Needs Setup**, **Unsupported** and **Unknown/Untested** so users can see the expected state before installation
- integrate Steam, Epic, GOG, Amazon Games and Heroic-backed library/store paths where supported while keeping the actual game licenses and downloads controlled by their respective services
- add anti-cheat compatibility setup/status helpers that install legitimate supported runtime prerequisites and surface the known Linux/Proton anti-cheat state for each game
- never claim to bypass or defeat anti-cheat; games whose vendor or anti-cheat intentionally blocks Linux/Proton must be marked unsupported until the vendor enables support
- allow compatibility profiles and anti-cheat status data to be updated independently through reviewed MechOS hotfix/update packages as game support changes

### USB4 and advanced controller support

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
