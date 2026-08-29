# MechOS Graphical Installation Architecture

## Live mode detection

`/usr/local/lib/mechos/runtime.sh` detects a Fedora live boot using `/run/initramfs/live` and live-kernel command line flags.

The same `mechscope.desktop` SDDM session is used on live and installed systems, but `mechscope-session` chooses a different default:

- live USB with no user preference -> KDE Desktop Mode
- installed system with no user preference -> MechScope Gaming Mode

This prevents the installer USB from dropping directly into Steam while preserving console-like boot behavior after installation.

## Welcome UI

`mechos-live-welcome` launches automatically in the live KDE session and gives the user graphical choices. `mechos-install` launches Fedora's `liveinst`, which starts the Anaconda WebUI when `anaconda-webui` is present.

## Installer branding

A MechOS branding override is installed under Cockpit's Fedora branding directory. Anaconda WebUI consumes Cockpit branding and `.anaconda` color/logo rules.

## Installed first boot

The existing `mechos-firstboot.service` discovers the newly created normal user, bootstraps Steam/RPM Fusion when network access exists, configures the GPU, sets the MechOS Plymouth theme, writes the gaming-mode preference, and configures SDDM autologin to MechScope.
