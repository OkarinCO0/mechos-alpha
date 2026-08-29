# MechOS GitHub build

This repository is prepared for a one-click GitHub Actions build.

1. Open **Actions** in the repository.
2. Select **Build MechOS ISO**.
3. Choose **Run workflow**.
4. Wait for the build job to finish.
5. Download the `MechOS-0.3.2-alpha-x86_64` artifact.
6. Extract the artifact and follow `REASSEMBLE.txt` to reassemble the ISO.

The workflow builds inside a privileged Fedora 44 container on a GitHub-hosted Ubuntu runner, verifies the generated SHA-256 checksum, and uploads split ISO parts for download.
