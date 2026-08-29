# MechOS architecture

## Sessions

`mechscope.desktop` is the default gaming session. `mechscope-session` reads `~/.config/mechos/session-mode`.

- `gaming`: starts Gamescope, then Steam Gamepad UI.
- `desktop`: starts KDE Plasma Wayland.

`mechos-session-select` changes the mode and ends the current login. With SDDM autologin, the same user immediately returns in the requested mode. `steamos-session-select` is a compatibility shim for software that expects a SteamOS-style session command.

## Graphics

- NVIDIA: RPM Fusion `akmod-nvidia`, DRM KMS enabled.
- AMD/Intel: Mesa Vulkan stack.
- Gamescope HDR is opt-in (`MECHOS_HDR=1`) because display/driver combinations vary.
- VRR is on by default and can be disabled with `MECHOS_DISABLE_VRR=1`.

## Steam

Steam is not forked. MechScope launches the upstream client using Gamepad/SteamOS flags. This keeps the Steam library, store, achievements, Steam Input, Proton and cloud features updateable by Valve.

## Branding

Plymouth owns boot branding. `STEAM_UPDATEUI_PNG_BACKGROUND` supplies a MechOS background for the Steam update/startup phase. Deeper Steam UI theming should be implemented as an optional, versioned layer rather than patching Steam binaries.
