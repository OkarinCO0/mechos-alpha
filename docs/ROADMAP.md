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

### MechOS OTA update system

- upgrade the current Update Center from an Arch/Flatpak-focused updater into a true MechOS OTA updater capable of delivering reviewed MechOS-owned runtime, UI and compatibility changes without requiring a full ISO reinstall
- publish a signed MechOS update manifest describing the update ID, channel, target MechOS version, required base version, changed packages/files, download locations, SHA-256 hashes, reboot requirement, release notes and rollback metadata
- verify manifest signatures and package/file hashes before any MechOS-owned update is installed; reject incomplete, unsigned or mismatched update payloads instead of applying them partially
- support lightweight hotfix releases such as **0.3.0-HF1**, **HF2** and **HF3** for MechScope, installer, RGB, Discord, compatibility profiles, recovery tools and other reviewed fixes that do not require users to download a replacement ISO
- support normal release upgrades such as **0.3.0 -> 0.3.1** through the same Update Center when the upgrade path has been explicitly tested and approved
- keep Arch repository updates and Flatpak updates as separate visible jobs so users can distinguish upstream package updates from MechOS-owned hotfixes and release upgrades
- download MechOS update payloads into a dedicated cache first, validate them completely, then apply them transactionally rather than modifying live files while they are still downloading
- create a Snapper pre-update snapshot when a supported root snapshot configuration exists and record the snapshot/update relationship so Recovery Center can offer a clear rollback target after a failed update
- stage replacements for MechOS-owned files under paths such as `/usr/local/bin`, `/usr/share/mechos`, desktop launchers, compatibility data and configuration snippets using packaged ownership/version metadata instead of blindly copying arbitrary GitHub source files onto the installed system
- restart only the affected MechOS user services/apps when safe, such as MechScope or helper daemons, and request a full reboot only for kernel, graphics-driver, systemd, bootloader or other reboot-sensitive changes
- preserve user configuration, Creator Mode selections, game profiles, custom power profiles, browser data and other user-owned state during hotfixes and release upgrades unless a documented migration is required
- add automatic rollback marking when a MechOS OTA transaction fails after changes begin, with Recovery Center options to inspect the failed update, restore the pre-update snapshot when available and retry later
- add update history showing MechOS version/hotfix ID, installed time, result, changed components, reboot state and rollback information alongside the existing Arch/Flatpak history
- expose release notes and a concise **What changed** summary before installation, including whether the update affects MechScope, drivers, Creator Mode, compatibility data, installer/recovery tools or only upstream packages
- support **Stable** and later opt-in **Testing** channels, keeping Stable as the default and preventing automatic channel switching without explicit user action
- do not execute arbitrary GitHub repository scripts directly on end-user systems; OTA content must come through reviewed, versioned and signed MechOS update artifacts/packages
- keep the disposable Live ISO non-updatable; Live users should download a newer ISO while installed systems receive supported hotfixes and release upgrades through Update Center
- integrate OTA jobs into the planned MechScope Downloads UI with download progress, verification, install state, failure/retry status and restart-required notification

### MechOS Bridge for Companion app

- add a lightweight **MechOS Bridge** service to installed MechOS systems in 0.3.1 so the operating system is ready for the Android/iOS MechOS Companion app planned for 0.4
- make the bridge **post-install only**: stage its runtime/service files only in the installed-system payload and install/enable them after MechOS has been installed; do not expose an active bridge daemon, listener or pairing endpoint from the disposable Live ISO
- run one persistent bridge service across **all installed MechOS modes — MechScope, Desktop Mode and Creator Mode** — so switching modes does not disconnect the paired Companion app or require separate per-mode bridge processes
- report the currently active MechOS mode through the bridge and automatically update Companion-visible state when the user moves between MechScope, Desktop Mode and Creator Mode
- keep the same paired-device identity, permissions, notification channel and approved remote actions available across all three modes, subject to the user's per-device permission settings
- integrate bridge controls directly into **MechScope Settings > Companion & Bridge**, while also providing an installed-system Desktop/Creator-accessible settings launcher so pairing, revocation and permissions can be managed without first switching back to MechScope
- provide a versioned local API between the Companion app and MechOS instead of allowing the mobile app to execute arbitrary shell commands on the PC
- make local-network pairing the default using a QR code or short one-time pairing code, with encrypted authenticated sessions and a clear paired-device/revoke screen
- keep the bridge local-network-only by default for 0.3.1; do not expose the service directly to the public internet or add cloud remote access until a separately reviewed secure design exists
- expose read-only system status through the bridge, including PC online state, active MechOS mode, running game/app, CPU/GPU/RAM usage, temperatures when available, network state, downloads, OTA update state and reboot-required status
- expose permission-controlled actions for opening MechScope, Desktop Mode or Creator Mode, launching approved games/apps, basic media controls, recording/stream controls and mobile keyboard/touchpad input without exposing unrestricted command execution
- require explicit confirmation for sensitive actions such as sleep, restart and shutdown and reject those actions from unpaired or revoked devices
- provide a bridge event/notification channel for completed downloads, update results, game crashes and future RadarAI/MechClip events so the Companion app can receive user-enabled alerts without polling the whole system continuously
- use granular per-device permissions so game launching, mode switching, power controls, notifications, system telemetry, media controls and creator integrations can each be enabled or disabled independently
- store pairing keys/tokens using protected per-user/system storage, never place them in normal logs, diagnostic bundles or plaintext MechOS configuration files
- run the normal bridge service with least privilege and isolate any narrowly required privileged operation behind a separate reviewed helper rather than running the entire bridge as root
- add connection rate limits, request validation, device revocation and session expiration so a paired phone cannot silently retain unlimited access forever
- require an installed-system marker before the bridge service can start and keep the unit disabled/masked or absent in Live runtime so accidental Live-session activation is not a supported path
- define stable bridge endpoints in 0.3.1 for mode state/switching, MechScope/library status, MechOS downloads/OTA, notifications and approved app/game launches so the 0.4 Companion app can build against a known interface
- reserve extension points for MechClip, RadarAI, VRChat creator helpers and other future Companion features without requiring those integrations to be fully implemented in the initial 0.3.1 bridge

### Post-install network connection setup

- add a dedicated **Network Connection** step to the installed-system post-install/OOBE flow before optional Creator downloads and the first MechScope handoff
- use NetworkManager as the backend so the setup screen works with the same networking stack used by Plasma after setup finishes
- automatically detect wired Ethernet, Wi-Fi adapters and currently active connections and clearly show whether the system already has working network access
- list nearby Wi-Fi networks with SSID, signal strength and security state, with **Refresh**, **Connect**, **Disconnect** and **Use Current Connection** actions
- support password-protected Wi-Fi and hidden-network entry without storing Wi-Fi passwords in MechOS-specific plaintext configuration files; credentials remain managed through NetworkManager's normal connection storage
- allow users with multiple network adapters to choose which Ethernet or Wi-Fi device they want to use during first setup
- provide controller, keyboard, mouse and touch navigation so post-install networking can be completed without dropping to the Plasma desktop
- add a simple connection test after selection that checks local link, gateway/DNS and internet reachability separately so a local network is not incorrectly reported as completely offline
- detect common captive-portal situations when possible and provide an **Open Sign-In Page** action using the system browser rather than attempting to bypass portal authentication
- allow **Continue Offline** at all times; lack of internet must not trap the user in OOBE or prevent MechOS from reaching Desktop Mode/MechScope
- if networking is skipped or fails, clearly mark online-dependent Creator installs, Flatpak downloads, updates and sign-ins as pending instead of presenting them as broken
- persist the selected NetworkManager connection for normal installed-system use so the same network can reconnect automatically after reboot when the user chooses auto-connect
- provide an optional **Forget Network** action for connections created during OOBE and preserve existing connections when the user chooses to keep them
- expose basic troubleshooting details such as adapter name, driver, IP address, gateway, DNS state and NetworkManager connection state without requiring terminal commands
- add **Network Setup** to MechScope Settings/Quick Actions after installation so the same controller-friendly network selector can be reopened later
- include post-install network status and connection failures in MechOS diagnostics while excluding saved Wi-Fi passwords and other credentials from diagnostic reports

### MechBrowser

- add a controller-friendly **MechBrowser** entry directly to the MechScope home/Quick Access experience so users can browse without switching to Desktop Mode
- use a maintained browser backend such as Firefox instead of creating a custom browser engine, keeping web security updates and site compatibility owned by the upstream browser
- launch the browser as a managed fullscreen/windowed application inside the persistent Plasma/MechScope session so closing it returns directly to MechScope instead of ending the gaming session
- provide large controller-first **Back**, **Forward**, **Refresh**, **Home**, address/search and tab controls while preserving normal browser keyboard and mouse behavior
- add on-screen keyboard support for URL/search entry and make all primary browser actions navigable by controller, keyboard, mouse and touch
- provide MechScope-friendly bookmarks/quick links for useful gaming destinations such as Steam Community, ProtonDB, PCGamingWiki, Discord, YouTube, Twitch and MechOS Help, while allowing users to add/remove their own favorites
- keep standard browser profiles, cookies, saved logins, privacy controls and private-browsing behavior under the browser's normal user account rather than inventing a separate insecure MechOS credential store
- save browser downloads to the user's normal Downloads folder and surface active/completed browser downloads in the planned MechScope Downloads UI when reliable integration is available
- route web links opened from MechScope, Creator Mode, Discord helpers, game compatibility pages and the MechOS Store through MechBrowser when the user chooses the gaming-mode browser path
- provide an obvious **Return to MechScope** action and correctly restore controller focus after the browser closes
- keep browser processes unprivileged and preserve normal browser sandboxing; MechBrowser must never require root access merely to browse, download or sign in to websites
- test video playback, WebRTC, Discord/voice web features, hardware video decode, fullscreen video and controller input on AMD, Intel and NVIDIA systems without making those features a requirement for basic browsing
- defer an in-game **Game Companion Browser** overlay to a later phase after MechBrowser v1 is stable; that later mode can open guides/wikis from Quick Actions while a game is running and return cleanly to the game without adding unnecessary overhead to 0.3.1 v1

### GPU compatibility database

- add a MechScope/Settings GPU compatibility database for AMD Radeon, Intel Arc/Iris/UHD and NVIDIA GeForce/RTX hardware
- automatically detect GPU model, PCI ID, active kernel driver, Vulkan device/driver, Mesa or NVIDIA userspace version, PRIME/hybrid-GPU state and Gamescope preflight result
- show clear support tiers such as **Verified**, **Compatible**, **Experimental**, **Legacy** and **Unsupported/Untested** instead of claiming universal GPU support
- maintain model/family profiles for current AMD Radeon, Intel Arc/Iris and NVIDIA RTX hardware, with separate legacy handling for older NVIDIA and older Vulkan-limited GPUs
- surface required package paths for each supported family, including Mesa/Vulkan packages for AMD and Intel and the correct NVIDIA kernel/userspace/32-bit package stack for RTX-class hardware
- verify and display 32-bit Vulkan/OpenGL readiness for Steam and Proton so a GPU is not marked Verified when only the 64-bit graphics stack is working
- add runtime health checks for Vulkan, Gamescope, MechScope fullscreen startup, PRIME render offload where applicable, hardware video encode/decode availability when detectable and driver/module mismatches
- allow hardware compatibility entries and driver-package recommendations to be updated through reviewed MechOS update/hotfix data without rebuilding the entire ISO
- provide a user-facing GPU details page with detected hardware, installed driver package/version, Vulkan status, MechScope status, known limitations and recommended fixes
- feed anonymous/manual test results into a reviewable compatibility matrix so specific GPU models can move from Untested to Compatible or Verified only after real hardware testing

### Per-game power profiles

- add a **Power Profile** control to each game in MechScope with built-in **Efficiency**, **Balanced**, **Performance** and **Custom** profiles plus a system-wide default
- identify games by Steam App ID when available and fall back to executable/path and launcher metadata for Lutris, Heroic and direct MechScope launches
- use Feral GameMode as the base temporary optimization layer so CPU governor, I/O priority, process priority, screensaver inhibition and supported GPU performance-state requests can activate only while the game is running
- use a MechOS per-game supervisor/wrapper rather than depending on GameMode having a separate `gamemode.ini` for every title; the supervisor should select the MechOS profile, request GameMode for the game process and restore state when the game exits
- integrate `powerprofilesctl` when the platform exposes power-profiles-daemon profiles and use safe `cpupower`/governor fallback logic only where the detected platform supports it
- allow per-game CPU policy choices such as powersave/efficiency, balanced/default and performance without requiring permanent global governor changes
- allow safe vendor-supported GPU performance-mode selection for AMD, Intel and NVIDIA where exposed by the installed driver, but do **not** change clocks, voltage, power limits or enable automatic GPU overclocking as part of normal power profiles
- integrate hybrid-GPU/PRIME selection so a per-game profile can prefer the discrete GPU on supported laptops while cleanly falling back when offload is unavailable
- support AC-power and battery-aware behavior so laptops can automatically use a lower-power game profile on battery or ask before switching to a high-performance profile
- restore the previous CPU/platform/GPU power state after normal game exit, crash, launcher failure or MechScope restart so a game cannot leave the desktop permanently stuck in a high-power mode
- provide a MechScope **Settings > Performance > Game Power Profiles** page showing the active game, selected profile, CPU/platform power state, GameMode state, GPU/offload state and whether each requested optimization was actually applied
- add controller-first profile selection from a game's properties page and an optional Quick Actions shortcut for temporarily overriding the current game's power profile
- expose per-game profile inheritance so users can set a global default, launcher default or individual-game override without duplicating configuration
- store user-created power profiles as readable local MechOS profile data and allow reviewed built-in game recommendations to be updated through the MechOS update/hotfix channel without overwriting user choices
- connect profile recommendations to the GPU compatibility database so unsupported driver/GPU controls are skipped instead of being applied blindly
- add diagnostics for profile activation/restore failures and include active power-profile state in the MechOS optimization report for performance troubleshooting

### Game crash protection and recovery

- add a MechOS **Game Crash Protection** supervisor around MechScope-launched games; the goal is to contain crashes, restore the gaming session and collect useful diagnostics rather than claiming MechOS can prevent every game or engine crash
- track the game process tree, launcher/runner, Steam App ID or executable identity, Proton/Wine version, Gamescope state, GPU/driver state, active power profile and launch timestamp so an abnormal exit has enough context for troubleshooting
- classify normal exits separately from crashes, signals, launcher failures and forced termination so MechScope does not show false crash warnings every time a user closes a game normally
- keep each launched game in a managed process group/user scope where practical so orphaned Wine/Proton/helper processes can be detected and cleaned up after an abnormal exit without killing unrelated desktop applications
- immediately restore the previous GameMode, CPU/platform power profile, GPU/offload state and other temporary MechOS per-game settings after a crash, matching GameMode's existing ability to clean up after exited clients
- return directly to the MechScope library/home screen when the game process crashes instead of leaving the user on a black screen, frozen launch card or abandoned fullscreen session
- if Gamescope remains healthy, recover only the game; if the Gamescope gaming layer itself fails, attempt one controlled gaming-layer restart and then fall back to the persistent Plasma session instead of entering a restart loop
- use `systemd-coredump`/`coredumpctl` when available to record crash metadata and stack information for native Linux processes, with storage/retention limits so crash diagnostics cannot fill the system drive
- capture per-title Proton/Wine logs only when enabled or when a crash-recovery diagnostic session is requested, and rotate old logs automatically to avoid permanent disk and performance overhead
- add a controller-friendly **Game Crashed** screen with **Relaunch**, **Safe Relaunch**, **View Details**, **Open Troubleshooter** and **Return to Library** actions
- make **Safe Relaunch** temporarily disable optional MechOS-added launch tweaks such as custom overlays, custom power-profile overrides and nonessential launch arguments while preserving the game's normal security/anti-cheat requirements and the user's original saved configuration
- detect repeated crashes for the same title within a short session and stop automatic relaunch attempts; offer Safe Relaunch or troubleshooting instead of creating an endless crash/restart loop
- connect crash history to the Windows game compatibility database so a title/profile with repeated confirmed failures can be flagged for review without automatically changing another user's compatibility status
- allow reviewed MechOS compatibility/hotfix data to recommend a different Proton/Wine runner or known-safe launch setting after a confirmed compatibility issue, while never silently replacing user-selected settings
- add optional pre-launch backup/checkpoint support only for **known, explicitly mapped local save/config paths** and keep it opt-in; do not claim universal save protection because many games use proprietary launchers, cloud saves or unknown/custom save locations
- surface Steam Cloud or launcher-managed cloud-save status when it can be read safely, but leave synchronization ownership to Steam/the game launcher rather than attempting to replace or bypass it
- cap crash dump, Proton/Wine log and recovery-history storage with automatic rotation and a user-facing **Clear Crash Data** control
- keep crash reports local by default; require explicit user permission before attaching logs or hardware data to a bug report, RadarAI report or future MechOS compatibility submission
- add crash diagnostics to the MechOS Optimization Report, including abnormal-exit count, last crash reason when known, recovery action taken, power-profile restoration result and Gamescope recovery result

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

### Windows game compatibility and MechScope Unified Store verification

- research Windows-only games outside the current MechScope store before listing them as compatible, including install path, launcher behavior, Proton/Wine version, graphics/runtime dependencies and known limitations
- add verified compatible Windows games and their install/compatibility profiles to the MechScope Unified Store rather than presenting untested titles as supported
- provide per-game Linux compatibility setup scripts/helpers for verified Windows-only games, including required legitimate runtimes, launch options, prefixes and Proton/Wine selection where testing shows they are needed
- add compatibility status labels such as **Verified**, **Playable**, **Needs Setup**, **Unsupported** and **Unknown/Untested** so users can see the expected state before installation
- add **S.T.A.L.K.E.R. G.A.M.M.A.** as a planned MechScope Unified Store title for 0.3.1, with a controller-friendly install/manage entry and compatibility profile designed for MechOS
- package an assisted S.T.A.L.K.E.R. G.A.M.M.A. setup workflow that configures a dedicated Proton/Wine prefix, a tested Proton-GE/UMU runner, Mod Organizer 2 integration, DX11 launch settings and required archive/runtime dependencies while leaving copyrighted game/mod downloads and license acceptance to their legitimate upstream sources
- generate a MechScope library shortcut after a successful GAMMA setup, track the selected runner/prefix and expose **Install**, **Repair**, **Update Setup**, **Launch**, **Open MO2** and **Remove Integration** actions without deleting user-owned game/mod files unless explicitly requested
- initially mark the GAMMA profile **Needs Setup/Testing** and promote it to **Playable** or **Verified** only after the complete install, launcher, save/load, MO2 and in-game test path has been validated on real MechOS hardware
- add **Star Citizen** as a planned MechScope Unified Store title for 0.3.1, using a controller-friendly install/manage entry that assists with the RSI Launcher and the tested MechOS Wine/Proton compatibility path rather than bundling the game in the ISO
- package a Star Citizen assisted setup workflow with a dedicated Wine/Proton prefix, required Windows runtime components, Vulkan/DXVK/VKD3D checks where applicable, launcher configuration, shader/cache directory handling and MechScope launch integration while keeping RSI authentication, game licensing and game downloads under Cloud Imperium Games/RSI control
- expose **Install Launcher**, **Repair Compatibility**, **Launch RSI Launcher**, **Launch Star Citizen**, **Open Prefix**, **Update Setup** and **Remove Integration** actions, preserving user-owned game data unless the user explicitly chooses to remove it
- initially mark the Star Citizen profile **Needs Setup/Testing** and only promote it to **Playable** or **Verified** after RSI Launcher login/update, game installation, Easy Anti-Cheat state, launch, persistent universe entry and representative gameplay have been validated on real MechOS hardware
- make the Star Citizen compatibility profile updateable through MechOS hotfix data so Wine/Proton runner, launcher workarounds and anti-cheat support status can be revised without rebuilding the ISO as upstream compatibility changes
- integrate Steam, Epic, GOG, Amazon Games and Heroic-backed library/store paths where supported while keeping the actual game licenses and downloads controlled by their respective services
- add anti-cheat compatibility setup/status helpers that install legitimate supported runtime prerequisites and surface the known Linux/Proton anti-cheat state for each game
- never claim to bypass or defeat anti-cheat; games whose vendor or anti-cheat intentionally blocks Linux/Proton must be marked unsupported until the vendor enables support
- allow compatibility profiles and anti-cheat status data to be updated independently through reviewed MechOS hotfix/update packages as game support changes

### USB4, HOTAS/joystick and advanced controller support

- USB4 and Thunderbolt-class device support using the Linux kernel and userspace authorization stack supported by the detected hardware
- MechScope/Settings USB4 device status for docks, storage, displays, networking and compatible external PCIe/eGPU devices
- USB4 hot-plug detection, connection/authorization status, reconnect handling and hardware diagnostics without promising support for devices unsupported by the Linux kernel or vendor firmware
- controller layout manager inside MechScope Settings with built-in Xbox, PlayStation, Nintendo/Switch Pro, Steam Controller/Steam Input and generic SDL-compatible layouts
- per-controller layout profiles with button remapping, stick inversion, deadzones, trigger ranges, sensitivity, controller order and profile save/restore
- advanced controller support for USB and Bluetooth pairing, battery state, calibration, input testing and disconnect/reconnect handling
- advanced mappings for supported gyro, touchpad, rear paddles/extra buttons, rumble/haptics and controller shortcut chords while falling back cleanly when hardware features are unavailable
- add native HOTAS and joystick device detection for supported USB HID/evdev/SDL flight controls, including flight sticks, throttles, rudder pedals, yokes and button boxes without requiring them to emulate an Xbox controller
- add a MechScope **HOTAS / Joystick Setup** page with live axis/button visualization, center/range calibration, axis inversion, deadzones, sensitivity and response-curve controls
- support multi-device HOTAS sets so a stick, throttle, pedals and button box can be combined into one saved MechOS control profile while retaining each physical device's identity
- support per-game HOTAS/joystick profiles with automatic profile selection at launch, manual overrides and import/export of readable local mappings without overwriting a game's own bindings
- add axis/button conflict detection and a controller test screen that shows raw and processed values so drift, miscalibration and duplicate bindings can be diagnosed before launching a game
- pass supported HOTAS/joystick devices through to native Linux and Proton/Wine games using the appropriate Linux input path, while preserving Steam Input when a title or user explicitly chooses Steam to manage the device
- expose optional force-feedback/haptic capability only when the Linux driver, physical device and game support it; unsupported devices should continue working as normal input devices without fake force-feedback claims
- include HOTAS/joystick reconnect handling and persistent profile matching so unplugging or rebooting does not require rebuilding mappings when the same recognized devices return
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

- MechOS Companion mobile app for Android/iOS with a controller-friendly remote dashboard for paired MechOS PCs
- use the 0.3.1 MechOS Bridge as the Companion app's authenticated local connection and control layer instead of creating a separate remote-control backend in the mobile app
- local-network-first pairing using a QR code or one-time pairing code, with encrypted authenticated connections and a clear paired-device/revoke screen
- show PC online/offline state, active MechOS mode, currently running game/app and basic CPU/GPU/RAM/temperature status when available
- remotely open MechScope, Desktop Mode or Creator Mode and launch approved games/apps from the paired PC without exposing unrestricted shell access
- view Steam/MechOS download progress, OTA update state, reboot-required notices and recent update results from the phone
- receive optional MechOS notifications for game crashes, RadarAI hardware/software alerts, failed updates, completed downloads and other user-enabled system events
- provide streaming/recording controls, basic media controls and a mobile text-entry/virtual-touchpad mode to make typing and navigation easier from MechScope
- provide confirmation-protected sleep, restart and shutdown actions and never allow sensitive system actions from an unpaired device
- keep remote-control permissions granular so users can disable game launching, power controls, notifications, telemetry/status sharing or other companion capabilities independently
- keep the first release local-network-only by default; defer internet/cloud remote access until a separately reviewed secure remote-access design is available
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