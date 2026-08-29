# MechOS cloud ISO build

This revision adds a GitHub Actions workflow that builds MechOS on a Fedora 44 userspace inside a privileged Linux runner.

## Run it

1. Put this folder in a GitHub repository.
2. Open **Actions**.
3. Select **Build MechOS ISO**.
4. Choose **Run workflow**.
5. When the run finishes, download the `MechOS-0.3.2-alpha-x86_64` artifact.
6. Extract all parts into one folder and follow `REASSEMBLE.txt`.

The workflow validates the project, builds the Fedora 44 KDE KIWI image, verifies its SHA-256 checksum, then splits the ISO into smaller parts for artifact transfer.

## Why split the ISO

A Fedora KDE live ISO is several gigabytes. Splitting it reduces the chance that a single huge artifact exceeds account storage/transfer limits. The final reassembled ISO is verified against the build-produced SHA-256 file.

## Important

This workflow still depends on GitHub's hosted runner allowing the privileged loop/mount operations KIWI needs. If GitHub changes hosted-runner privileges, use a Fedora 44 machine or a self-hosted Fedora runner instead.
