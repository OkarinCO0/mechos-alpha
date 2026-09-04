# MechOS VM first-boot runtime

For VirtualBox/VMware/QEMU installs, Plasma remains the compositor. The required sequence is:

1. Native Clean Install writes `/var/lib/mechos/installed`.
2. `mechos-firstboot-authority.service` runs before SDDM when OOBE is incomplete.
3. SDDM autologs into the temporary `mechos-setup` Plasma session.
4. `mechos-oobe-start` launches account creation after the graphical session is ready.
5. MechScope and Creator Mode are blocked while `/var/lib/mechos/oobe-complete` is absent.
6. OOBE creates the permanent account, switches SDDM to the MechScope session, and reboots.
7. On VM boot, Plasma remains host compositor. MechScope starts fullscreen through `mechos-vm-mode-runtime`.
8. Creator Mode uses the same VM mode runtime. If a systemd user service cannot stay active, the runtime falls back to launching the requested fullscreen app directly in the current Plasma session.

This path intentionally avoids Gamescope inside virtual machines.