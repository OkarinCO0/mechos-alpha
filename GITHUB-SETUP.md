# MechOS GitHub Actions

Two workflows are included:

- **Validate MechOS Source** runs on pull requests, pushes to `main`, and manual dispatch.
- **Build MechOS Arch ISO** runs only when manually dispatched because a complete ISO build is large and slow.

## Build an ISO

1. Open **Actions** in `mechgod102-sketch/mechos`.
2. Select **Build MechOS Arch ISO**.
3. Select **Run workflow**.
4. When the build succeeds, download `MechOS-v0.3.0-alpha-x86_64`.
5. Verify `MechOS-Arch-Creator-x86_64.iso` with the included `.sha256` file.

Do not merge a change when **Validate MechOS Source** is failing. A successful static check does not replace booting and installing the produced ISO in a virtual machine.
