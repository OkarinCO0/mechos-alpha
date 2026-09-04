# MechOS Plymouth boot path

MechOS has two boot environments that must both request Plymouth:

1. **Live ISO** — the ArchISO mkinitcpio configuration must contain the `plymouth` hook and every Live bootloader entry must include `quiet splash`.
2. **Installed native Clean Install** — the native installer extracts the MechOS payload, reasserts the `mechos` Plymouth theme, inserts `plymouth` into the target mkinitcpio configuration (including drop-ins), adds `quiet splash` to GRUB defaults, rebuilds initramfs, and then generates `grub.cfg`.

The native Clean Install path does **not** execute the historical `mechos-postinstall-target` script. Splash behavior that exists only in that script is therefore not sufficient for current MechOS installs.

Final build authority is `scripts/mechos-plymouth-boot-final.sh`, which runs after `mechos-reference-splash-integration.sh`.