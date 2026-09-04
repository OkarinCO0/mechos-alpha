# MechOS v0.3.0 Release Certification

Use this document for every v0.3.0 release candidate. A release is **NO-GO** if any BLOCKER item fails.

## Release candidate metadata

- RC / build ID: ____________________
- Git commit: ____________________
- ISO filename: ____________________
- SHA256: ____________________
- Test date: ____________________
- Tester: ____________________
- VM platform: ____________________
- Physical hardware: ____________________
- GPU / driver: ____________________

Status key: `PASS` / `FAIL` / `N/A` / `NOT TESTED`

---

## 1. Build and artifact gate — BLOCKER

- [ ] PASS — Brand-new `Build MechOS Arch ISO` workflow started from current `main`.
- [ ] PASS — Source validation completed successfully.
- [ ] PASS — ISO build completed without errors.
- [ ] PASS — `.iso` exists and is non-empty.
- [ ] PASS — `.iso.sha256` exists.
- [ ] PASS — `sha256sum -c` passes.
- [ ] PASS — GitHub artifact upload completes.
- [ ] PASS — Release candidate commit SHA matches the intended `main` commit.

Notes / evidence:

```text

```

## 2. Live ISO boot gate — BLOCKER

- [ ] PASS — UEFI boot succeeds.
- [ ] PASS — MechOS splash appears correctly.
- [ ] PASS — KDE Plasma live desktop appears.
- [ ] PASS — Setup / Installer opens without crashing.
- [ ] PASS — Network works in Live mode.
- [ ] PASS — Audio works in Live mode.
- [ ] PASS — Display resolution can be changed.
- [ ] PASS — No unexpected crash/fallback dialogs appear.
- [ ] PASS — Live environment does not expose installed-only Creator Mode as the normal default workflow.

## 3. Clean installation gate — BLOCKER

Test on a blank virtual disk first, then on dedicated physical test hardware.

- [ ] PASS — Installer detects the intended target disk.
- [ ] PASS — Wrong disks are not preselected or erased.
- [ ] PASS — Partitioning completes.
- [ ] PASS — Bootloader installs.
- [ ] PASS — User account creation succeeds.
- [ ] PASS — Locale, timezone and keyboard settings persist.
- [ ] PASS — Installation completes without manual repair.
- [ ] PASS — ISO can be removed after installation.
- [ ] PASS — Installed disk boots by itself.

## 4. OOBE and installed login gate — BLOCKER

- [ ] PASS — OOBE starts on first boot.
- [ ] PASS — Welcome step works.
- [ ] PASS — Account step works.
- [ ] PASS — Region / timezone step works.
- [ ] PASS — Device / profile step works.
- [ ] PASS — Review / Finish works.
- [ ] PASS — OOBE does not repeat after successful completion.
- [ ] PASS — SDDM selects the real `mechscope.desktop` session after OOBE.
- [ ] PASS — Installed user's session mode is initialized to `gaming`.

## 5. MechScope installed-system gate — BLOCKER

- [ ] PASS — MechScope starts automatically after install.
- [ ] PASS — No black screen.
- [ ] PASS — No old stripped MechScope shell appears.
- [ ] PASS — Approved MechScope 2.0 GUI appears.
- [ ] PASS — UI scales correctly at 1280x720.
- [ ] PASS — UI scales correctly at 1920x1080.
- [ ] PASS — Steam Library opens.
- [ ] PASS — Unified Store opens.
- [ ] PASS — Performance Center opens.
- [ ] PASS — Update Center opens.
- [ ] PASS — Creator Mode opens.
- [ ] PASS — Recovery opens.
- [ ] PASS — Quick Actions opens.
- [ ] PASS — Power / reboot / shutdown controls work.
- [ ] PASS — Reboot returns to MechScope again.
- [ ] PASS — `~/.local/state/mechos/mechscope-session.log` contains no fatal startup loop.

## 6. Mode switching gate — BLOCKER

Repeat each transition several times.

- [ ] PASS — MechScope → Desktop Mode.
- [ ] PASS — Desktop Mode → MechScope.
- [ ] PASS — MechScope → Creator Mode.
- [ ] PASS — Creator Mode → MechScope.
- [ ] PASS — Gaming → Desktop → Creator → Gaming.
- [ ] PASS — Mode switching still works after reboot.
- [ ] PASS — No duplicate MechScope / Creator Mode processes remain running.
- [ ] PASS — No runaway CPU or RAM growth after repeated switching.

## 7. Virtual machine certification

VirtualBox is for install/UI/runtime validation, not gaming-performance certification.

- [ ] PASS — `systemd-detect-virt` identifies the VM.
- [ ] PASS — Gamescope is bypassed in the VM path.
- [ ] PASS — Plasma supplies the compositor while MechScope still launches fullscreen.
- [ ] PASS — Creator Mode renders correctly.
- [ ] PASS — Installer renders correctly.
- [ ] PASS — OOBE renders correctly.
- [ ] PASS — 1280x720 layout is usable.
- [ ] PASS — Higher VM resolution is usable if available.
- [ ] PASS — Rebooted installed VM reaches MechScope.
- [ ] PASS — Update Center opens.
- [ ] PASS — Recovery opens.

## 8. Physical hardware certification — BLOCKER

Minimum: one real PC. Preferred: AMD, NVIDIA and Intel graphics coverage.

System A:
- CPU: ____________________
- GPU: ____________________
- RAM: ____________________
- Storage: ____________________
- Result: ____________________

System B:
- CPU: ____________________
- GPU: ____________________
- RAM: ____________________
- Storage: ____________________
- Result: ____________________

- [ ] PASS — Native boot works on physical hardware.
- [ ] PASS — MechScope starts on physical hardware.
- [ ] PASS — Gamescope path works or cleanly falls back.
- [ ] PASS — Display output is correct.
- [ ] PASS — Audio is correct.
- [ ] PASS — Network is correct.
- [ ] PASS — Suspend / resume is stable.

## 9. GPU / Vulkan / display gate — BLOCKER

- [ ] PASS — `vulkaninfo` runs.
- [ ] PASS — Vulkan reports the real GPU, not a software renderer.
- [ ] PASS — AMD path works if tested.
- [ ] PASS — NVIDIA path works if tested.
- [ ] PASS — Intel graphics path works if tested.
- [ ] PASS — Hardware acceleration is active.
- [ ] PASS — Gamescope launches on supported real hardware.
- [ ] PASS — 60 Hz works.
- [ ] PASS — High refresh rate works where supported.
- [ ] PASS — Multi-monitor behavior is acceptable.
- [ ] PASS — VRR works where supported or fails safely when unsupported.

## 10. Steam / Proton gaming gate — BLOCKER

Record game, Proton version, GPU, result and notes.

| Category | Game | Proton | Result | Notes |
|---|---|---|---|---|
| Native Linux |  |  |  |  |
| DX11 Proton |  |  |  |  |
| DX12 Proton |  |  |  |  |
| AAA / demanding |  |  |  |  |
| Multiplayer |  |  |  |  |
| Controller-first |  |  |  |  |

For each tested game:
- [ ] Launches.
- [ ] Audio works.
- [ ] Controller works if applicable.
- [ ] Frame pacing is reasonable.
- [ ] Exit returns cleanly to MechScope.
- [ ] Mode switching does not corrupt the session.

### Overwatch regression check

- [ ] PASS — Physical-hardware performance tested.
- [ ] PASS — Desktop Mode tested.
- [ ] PASS — MechScope / Gamescope tested.
- [ ] PASS — Proton Experimental tested.
- [ ] PASS — Vulkan uses the real GPU.
- [ ] PASS — No unexplained ~10 FPS regression remains on supported hardware.

## 11. Controller gate

- [ ] PASS — Xbox controller wired.
- [ ] PASS — Xbox controller Bluetooth if available.
- [ ] PASS — PlayStation controller if available.
- [ ] PASS — Steam Input works.
- [ ] PASS — MechScope can be navigated without keyboard/mouse.
- [ ] PASS — Focus indicators are visible.
- [ ] PASS — Controller reconnect works after sleep / reboot where expected.

## 12. Network and Bluetooth gate

- [ ] PASS — Ethernet.
- [ ] PASS — Wi-Fi.
- [ ] PASS — Wi-Fi reconnect after reboot.
- [ ] PASS — DNS resolution.
- [ ] PASS — Browser access.
- [ ] PASS — Steam downloads.
- [ ] PASS — Bluetooth enable / disable.
- [ ] PASS — Bluetooth controller pairing.
- [ ] PASS — Bluetooth audio pairing.
- [ ] PASS — Bluetooth reconnect after reboot.

## 13. Audio gate

- [ ] PASS — Built-in speakers / analog output if available.
- [ ] PASS — Headphones.
- [ ] PASS — HDMI / DisplayPort audio.
- [ ] PASS — USB headset if available.
- [ ] PASS — Microphone input.
- [ ] PASS — Steam game audio.
- [ ] PASS — OBS capture audio.
- [ ] PASS — Device switching works.

## 14. Creator Mode gate — BLOCKER for advertised creator features

- [ ] PASS — Approved Creator Mode reference-backed UI appears.
- [ ] PASS — Unity Hub action works.
- [ ] PASS — Blender action works.
- [ ] PASS — Unreal Engine action works.
- [ ] PASS — OBS Studio action works.
- [ ] PASS — Krita action works.
- [ ] PASS — Kdenlive action works.
- [ ] PASS — Godot action works.
- [ ] PASS — VRChat Creator tools action works.
- [ ] PASS — Creator Store opens.
- [ ] PASS — Project profiles work.
- [ ] PASS — Installed/not-installed app states do not silently fail.
- [ ] PASS — Back to MechScope works.

## 15. Performance Center / RadarAI gate

- [ ] PASS — CPU info is reasonable.
- [ ] PASS — RAM info is reasonable.
- [ ] PASS — GPU detection is correct.
- [ ] PASS — Disk information is correct.
- [ ] PASS — Temperatures display where supported.
- [ ] PASS — Auto Optimization does not destabilize the system.
- [ ] PASS — Intended settings persist after reboot.
- [ ] PASS — RadarAI logging works.
- [ ] PASS — RadarAI user notifications do not loop or spam.
- [ ] PASS — Network/reporting failure does not freeze the UI.
- [ ] PASS — No secrets, personal data or unintended logs are submitted.

## 16. Update Center gate — BLOCKER

- [ ] PASS — Fully updated system reports correctly.
- [ ] PASS — Real MechOS update can be installed.
- [ ] PASS — Reboot after update succeeds.
- [ ] PASS — MechScope still starts after update.
- [ ] PASS — Creator Mode still starts after update.
- [ ] PASS — Custom MechOS files are not unexpectedly overwritten.
- [ ] PASS — Failed/interrupted update produces a recoverable state.
- [ ] PASS — Package database repair path works.

## 17. Recovery gate — BLOCKER

- [ ] PASS — Recovery Center opens.
- [ ] PASS — Boot repair path works on a controlled test case.
- [ ] PASS — Package repair path works.
- [ ] PASS — Update repair path works.
- [ ] PASS — Desktop fallback works.
- [ ] PASS — Broken MechScope can be recovered.
- [ ] PASS — User files are preserved where promised.
- [ ] PASS — Recovery never selects or wipes the wrong disk without explicit confirmation.

## 18. Suspend / resume gate

- [ ] PASS — Suspend succeeds.
- [ ] PASS — Wake succeeds.
- [ ] PASS — GPU recovers.
- [ ] PASS — Wi-Fi recovers.
- [ ] PASS — Bluetooth recovers.
- [ ] PASS — Audio recovers.
- [ ] PASS — MechScope remains usable.

## 19. Storage gate

- [ ] PASS — NVMe installation / use.
- [ ] PASS — SATA SSD if available.
- [ ] PASS — USB storage mount.
- [ ] PASS — Secondary Steam library drive.
- [ ] PASS — NTFS/Windows game drive handling if supported.
- [ ] PASS — Low disk space is handled safely.
- [ ] PASS — Nearly-full root filesystem does not corrupt update/install state.

## 20. Installer safety gate — BLOCKER

Use disposable test disks only.

- [ ] PASS — Multiple-disk system tested.
- [ ] PASS — Existing Windows disk detected without accidental erasure.
- [ ] PASS — Existing Linux disk detected without accidental erasure.
- [ ] PASS — Existing EFI partition case tested.
- [ ] PASS — Blank/unformatted disk tested.
- [ ] PASS — Cancel installation path works.
- [ ] PASS — Re-running installer after cancel works.
- [ ] PASS — Destructive action always requires explicit target/confirmation.

## 21. GUI reference audit

Capture screenshots from the actual built/installed OS and compare with approved references.

| Surface | Screenshot captured | Matches approved reference | Notes |
|---|---|---|---|
| Boot splash | [ ] | [ ] | |
| Installer | [ ] | [ ] | |
| OOBE | [ ] | [ ] | |
| MechScope | [ ] | [ ] | |
| Creator Mode | [ ] | [ ] | |
| Performance Center | [ ] | [ ] | |
| Update Center | [ ] | [ ] | |
| Recovery | [ ] | [ ] | |
| Quick Actions | [ ] | [ ] | |

## 22. Release hygiene gate — BLOCKER

- [ ] PASS — No test/default passwords are published unintentionally.
- [ ] PASS — No API keys.
- [ ] PASS — No GitHub tokens.
- [ ] PASS — No secrets in shell history, logs or config.
- [ ] PASS — No build-only `/workspace/...` paths are required at runtime.
- [ ] PASS — No debug usernames or machine-specific paths.
- [ ] PASS — Temporary build files are excluded.
- [ ] PASS — Debug logging is not excessive.
- [ ] PASS — Version is correct everywhere.
- [ ] PASS — Release notes written.
- [ ] PASS — Known issues documented.
- [ ] PASS — SHA256 published with ISO.
- [ ] PASS — Installation instructions published.
- [ ] PASS — Recovery instructions published.
- [ ] PASS — Game compatibility wording does not promise unsupported anti-cheat compatibility.

---

# Hard GO / NO-GO gate

A public v0.3.0 release is **GO** only when all of these are PASS:

- [ ] Successful ISO build + checksum
- [ ] Live boot
- [ ] Clean installation
- [ ] OOBE
- [ ] Installed MechScope
- [ ] Desktop / Creator / Gaming mode switching
- [ ] Reboot persistence
- [ ] At least one physical-hardware certification
- [ ] Vulkan / real GPU validation
- [ ] Steam / Proton game test suite
- [ ] Creator Mode advertised features
- [ ] Update Center
- [ ] Recovery
- [ ] Installer safety
- [ ] Release hygiene

## Final decision

- [ ] **GO — release approved**
- [ ] **NO-GO — release blocked**

Blocking failures:

```text

```

Known non-blocking issues accepted for this release:

```text

```

Approved by: ____________________

Date: ____________________
