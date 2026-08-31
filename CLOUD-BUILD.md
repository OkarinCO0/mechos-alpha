# MechOS cloud ISO build

The `Build MechOS Arch ISO` workflow builds MechOS inside a privileged `archlinux:latest` container on an Ubuntu GitHub-hosted runner.

## Run it

1. Open the repository's **Actions** page.
2. Select **Build MechOS Arch ISO**.
3. Choose **Run workflow**.
4. Wait for validation, integration, ISO build and checksum verification to finish.
5. Download the `MechOS-v0.3.0-alpha-x86_64` artifact.
6. Extract `MechOS-Arch-Creator-x86_64.iso` and its `.sha256` file.
7. Verify the checksum before testing the ISO.

## Workflow behavior

- Static validation runs before package downloads or ArchISO work.
- The cumulative MechOS integration patch is applied idempotently.
- ArchISO runs in a privileged Docker container.
- The ISO is checked against its SHA-256 file before upload.
- Only one cloud ISO build runs at a time.
- Artifacts are retained for seven days to reduce storage usage.

GitHub-hosted runners must continue to support privileged Docker and have enough disk space. If that changes, use a Linux host with Docker or a self-hosted runner.
