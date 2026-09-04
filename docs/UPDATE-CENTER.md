# MechOS Update Center v1

Update Center v1 ships with MechOS v0.3.0 so installed systems have an upgrade path to v0.3.1 and later releases without reinstalling the OS.

## What v1 updates

- MechOS release metadata and verified MechOS-owned update bundles
- Arch Linux packages through `pacman -Syu`
- System Flatpaks
- User Flatpaks when Update Center was authorized through `pkexec`
- Update history and reboot-required state

The Live ISO is intentionally read-only from Update Center. Install MechOS before using the updater.

## Stable channel

The stable channel manifest is committed at:

```text
updates/stable.json
```

Installed systems fetch:

```text
https://raw.githubusercontent.com/mechgod102-sketch/mechos/main/updates/stable.json
```

The ISO also contains a local copy of the manifest as a safe metadata fallback.

A manifest announces:

- release version
- release name
- release notes
- HTTPS update-bundle URL
- SHA-256 for that bundle
- reboot requirement

A newer release must not be announced until both the bundle URL and its final SHA-256 are available.

## Safety model

Before package changes, Update Center creates a Snapper root snapshot when a compatible root Snapper profile exists. The snapshot ID is stored under `/var/lib/mechos`.

MechOS-owned bundles are accepted only when:

1. the manifest validates;
2. the bundle URL uses HTTPS;
3. the downloaded bundle exactly matches the manifest SHA-256; and
4. every bundle member is inside the MechOS-owned path allowlist.

Update Center does not download and execute arbitrary release scripts. The verified archive is copied only into approved MechOS system paths.

If the system update fails after a snapshot was created, `/var/lib/mechos/rollback-pending` records that recovery protection is available.

## Publishing v0.3.1

Build and test the v0.3.1 installed root filesystem first. Then create the MechOS-owned update bundle:

```bash
bash scripts/build-mechos-update-bundle.sh \
  0.3.1-alpha \
  /path/to/extracted/installed/rootfs \
  out/MechOS-0.3.1-alpha-update.tar.zst
```

The command creates the bundle and a `.sha256` file, then prints the values that belong in `updates/stable.json`.

Upload the bundle as a GitHub Release asset. Verify the public asset checksum before changing the stable manifest. Then update all of these fields together:

```json
{
  "version": "0.3.1-alpha",
  "release_name": "MechOS v0.3.1 Alpha",
  "notes": "Release notes for the update.",
  "bundle_url": "https://github.com/mechgod102-sketch/mechos/releases/download/v0.3.1-alpha/MechOS-0.3.1-alpha-update.tar.zst",
  "bundle_sha256": "<64 hex characters>",
  "requires_reboot": true
}
```

## Required v0.3.0 release test

Before publishing v0.3.0, perform one end-to-end update simulation on an installed test machine:

1. Install the final v0.3.0 release candidate.
2. Point `/etc/mechos/update.conf` at a temporary test manifest you control.
3. Publish a harmless test bundle with a higher test version and a known SHA-256.
4. Open Update Center and confirm Current and Latest versions are displayed correctly.
5. Confirm release notes appear.
6. Install the test update.
7. Confirm the pre-update snapshot is created when Snapper is available.
8. Confirm the bundle checksum is verified before files are changed.
9. Confirm `/etc/mechos/release` advances only after a successful bundle install.
10. Reboot when requested and verify MechScope, Creator Mode, Update Center and Recovery still open.
11. Restore the stable channel configuration and test that the system reports current/up-to-date.

Do not mark the v0.3.0 Update Center release gate PASS until this transition test succeeds.
