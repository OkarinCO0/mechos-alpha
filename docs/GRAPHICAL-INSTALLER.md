# MechOS installation architecture

## Live-mode detection

MechOS detects ArchISO through `/run/archiso/bootmnt` and ArchISO kernel-command-line values. Live-only setup and first-boot provisioning therefore do not run on the wrong side of installation.

## Setup Center

The PyQt Setup Center opens over KDE Plasma and provides installation, recovery and hardware-scan actions. Closing it leaves the live desktop available.

## Archinstall handoff

**Install MechOS** starts a guided Archinstall terminal. The partial configuration adds the local MechOS post-install payload but does not select, partition or format a disk. Archinstall displays the disk plan and requires final confirmation.

## Installed-system handoff

After Archinstall creates the target system, the MechOS post-install stage:

- enables multilib;
- installs the Plasma, gaming, graphics and creator foundation;
- extracts the installed-system MechOS payload;
- selects the real desktop user;
- removes live-only account and autostart files;
- configures SDDM and MechOS Gaming;
- enables stable services;
- applies GPU-specific packages;
- validates required runtime files before reporting success.
