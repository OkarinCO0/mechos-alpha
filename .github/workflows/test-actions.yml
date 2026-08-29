name: Build MechOS Arch ISO

on:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  build-iso:
    runs-on: ubuntu-24.04
    timeout-minutes: 180

    steps:
      - name: Checkout MechOS
        uses: actions/checkout@v4

      - name: Free disk space
        shell: bash
        run: |
          set -eux
          df -h
          sudo rm -rf /usr/local/lib/android || true
          sudo rm -rf /usr/share/dotnet || true
          sudo rm -rf /opt/ghc || true
          sudo rm -rf /usr/local/.ghcup || true
          sudo rm -rf /opt/hostedtoolcache || true
          sudo docker system prune -af --volumes || true
          sudo apt-get clean || true
          df -h

      - name: Build MechOS Arch ISO
        shell: bash
        run: |
          set -euxo pipefail

          mkdir -p "$GITHUB_WORKSPACE/out"

          docker run --rm --privileged \
            -v /dev:/dev \
            -v "$GITHUB_WORKSPACE:/workspace" \
            -w /workspace \
            archlinux:latest \
            bash -lc '
              set -euxo pipefail

              pacman -Syu --noconfirm
              pacman -S --noconfirm archiso git rsync sed grep coreutils findutils

              rm -rf /workspace/archlive /workspace/work
              cp -a /usr/share/archiso/configs/releng /workspace/archlive

              # Enable multilib for Steam and 32-bit gaming libraries.
              sed -i "/^\#\[multilib\]/,/^\#Include = \/etc\/pacman.d\/mirrorlist/ s/^\#//" \
                /workspace/archlive/pacman.conf

              # MechOS gaming + desktop packages.
              cat >> /workspace/archlive/packages.x86_64 << "PKGS"
plasma-meta
sddm
konsole
dolphin
ark
kate
networkmanager
network-manager-applet
bluez
bluez-utils
pipewire
pipewire-alsa
pipewire-pulse
wireplumber
xdg-desktop-portal
xdg-desktop-portal-kde
steam
gamescope
lutris
gamemode
lib32-gamemode
mangohud
lib32-mangohud
wine
wine-mono
wine-gecko
winetricks
protontricks
vulkan-tools
mesa
lib32-mesa
vulkan-radeon
lib32-vulkan-radeon
vulkan-intel
lib32-vulkan-intel
nvidia
nvidia-utils
lib32-nvidia-utils
linux
linux-headers
linux-firmware
linux-firmware-whence
ntfs-3g
exfatprogs
btrfs-progs
dosfstools
e2fsprogs
f2fs-tools
xfsprogs
openssh
git
curl
wget
unzip
zip
p7zip
flatpak
PKGS

              # Reuse the existing MechOS root filesystem overlay.
              if [ -d /workspace/overlay/rootfs ]; then
                rsync -aHAX --numeric-ids /workspace/overlay/rootfs/ /workspace/archlive/airootfs/
              fi

              # Arch-specific defaults.
              mkdir -p /workspace/archlive/airootfs/etc/sddm.conf.d
              cat > /workspace/archlive/airootfs/etc/sddm.conf.d/mechos.conf << "EOF"
[Autologin]
User=mechos
Session=plasma.desktop
Relogin=true
EOF

              # Create the default live user.
              mkdir -p /workspace/archlive/airootfs/etc/systemd/system/getty@tty1.service.d
              cat > /workspace/archlive/airootfs/etc/systemd/system/getty@tty1.service.d/autologin.conf << "EOF"
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin mechos --noclear %I $TERM
EOF

              # Ensure groups/user exist in the live image.
              cat >> /workspace/archlive/airootfs/etc/passwd << "EOF"
mechos:x:1000:1000:MechOS Live User:/home/mechos:/bin/bash
EOF
              cat >> /workspace/archlive/airootfs/etc/group << "EOF"
mechos:x:1000:
EOF
              cat >> /workspace/archlive/airootfs/etc/shadow << "EOF"
mechos::20000:0:99999:7:::
EOF
              mkdir -p /workspace/archlive/airootfs/home/mechos
              chown -R 1000:1000 /workspace/archlive/airootfs/home/mechos

              # Boot to graphical mode.
              mkdir -p /workspace/archlive/airootfs/etc/systemd/system
              ln -sf /usr/lib/systemd/system/graphical.target \
                /workspace/archlive/airootfs/etc/systemd/system/default.target

              # Enable core services in the image.
              mkdir -p /workspace/archlive/airootfs/etc/systemd/system/multi-user.target.wants
              ln -sf /usr/lib/systemd/system/NetworkManager.service \
                /workspace/archlive/airootfs/etc/systemd/system/multi-user.target.wants/NetworkManager.service
              ln -sf /usr/lib/systemd/system/bluetooth.service \
                /workspace/archlive/airootfs/etc/systemd/system/multi-user.target.wants/bluetooth.service
              mkdir -p /workspace/archlive/airootfs/etc/systemd/system/display-manager.service.wants
              ln -sf /usr/lib/systemd/system/sddm.service \
                /workspace/archlive/airootfs/etc/systemd/system/display-manager.service

              # MechOS ISO identity.
              sed -i "s/^iso_name=.*/iso_name=\"mechos\"/" /workspace/archlive/profiledef.sh
              sed -i "s/^iso_label=.*/iso_label=\"MECHOS_$(date +%Y%m)\"/" /workspace/archlive/profiledef.sh
              sed -i "s/^iso_publisher=.*/iso_publisher=\"MechOS\"/" /workspace/archlive/profiledef.sh
              sed -i "s/^iso_application=.*/iso_application=\"MechOS Gaming Linux\"/" /workspace/archlive/profiledef.sh

              mkdir -p /workspace/out /workspace/work
              mkarchiso -v \
                -w /workspace/work \
                -o /workspace/out \
                /workspace/archlive

              ISO="$(find /workspace/out -maxdepth 1 -type f -name "*.iso" | head -n1)"
              test -n "$ISO"

              FINAL=/workspace/out/MechOS-Arch-x86_64.iso
              mv "$ISO" "$FINAL"
              sha256sum "$FINAL" > "$FINAL.sha256"

              ls -lh /workspace/out
            '

      - name: Verify ISO
        shell: bash
        run: |
          set -euxo pipefail
          test -f out/MechOS-Arch-x86_64.iso
          test -f out/MechOS-Arch-x86_64.iso.sha256
          cd out
          sha256sum -c MechOS-Arch-x86_64.iso.sha256
          ls -lh

      - name: Upload MechOS ISO
        uses: actions/upload-artifact@v4
        with:
          name: MechOS-Arch-x86_64
          path: |
            out/MechOS-Arch-x86_64.iso
            out/MechOS-Arch-x86_64.iso.sha256
          compression-level: 0
          retention-days: 7
          if-no-files-found: error
