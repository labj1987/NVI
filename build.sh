#!/usr/bin/env bash
set -euo pipefail

PKG_NAME="nvidia-driver-installer"
VERSION="2.3.0"
ARCH="amd64"
DEB_NAME="${PKG_NAME}_${VERSION}_${ARCH}.deb"
STAGING="/tmp/${PKG_NAME}-staging"

echo "==> Checking build dependencies…"
apt-get install -y \
    cargo \
    rustc \
    libgtk-4-dev \
    libadwaita-1-dev \
    pkg-config \
    libssl-dev \
    dpkg-dev

echo "==> Building release binary…"
cargo build --release

echo "==> Staging package layout…"
rm -rf "$STAGING"

install -Dm755 "target/release/${PKG_NAME}" \
    "${STAGING}/usr/bin/${PKG_NAME}"

install -Dm755 "scripts/privileged-install.sh" \
    "${STAGING}/usr/lib/${PKG_NAME}/privileged-install.sh"

install -Dm644 "data/com.lordnikon.nvidia-driver-installer.policy" \
    "${STAGING}/usr/share/polkit-1/actions/com.lordnikon.nvidia-driver-installer.policy"

install -Dm644 "data/nvidia-driver-installer.desktop" \
    "${STAGING}/usr/share/applications/nvidia-driver-installer.desktop"

# DBus service file — tells GNOME Shell to route dock clicks to running instance
install -Dm644 "data/com.lordnikon.nvidia-driver-installer.service" \
    "${STAGING}/usr/share/dbus-1/services/com.lordnikon.nvidia-driver-installer.service"

# Icons
for size in 16 32 48 64 128 256 512; do
    install -Dm644 "data/nvidia-driver-installer-${size}.png" \
        "${STAGING}/usr/share/icons/hicolor/${size}x${size}/apps/nvidia-driver-installer.png"
done

echo "==> Writing DEBIAN metadata…"
mkdir -p "${STAGING}/DEBIAN"

cat > "${STAGING}/DEBIAN/control" << CTRL
Package: ${PKG_NAME}
Version: ${VERSION}
Section: admin
Priority: optional
Architecture: ${ARCH}
Depends: policykit-1 | polkitd, pkexec, libgtk-4-1, libadwaita-1-0, dkms, build-essential
Maintainer: Linnard Alex Brown Jr. <alex@lordnikon.local>
Description: NVIDIA Driver Installer
 GTK4 + Rust GUI for installing NVIDIA .run drivers on Ubuntu.
 Supports version browsing, download with SHA256 verification,
 DKMS integration, and polkit-authorized privileged installation.
CTRL

cat > "${STAGING}/DEBIAN/postinst" << 'POST'
#!/bin/bash
set -e
chmod +x /usr/lib/nvidia-driver-installer/privileged-install.sh
chmod 755 /usr/lib/nvidia-driver-installer/
chmod 644 /usr/share/polkit-1/actions/com.lordnikon.nvidia-driver-installer.policy
gtk-update-icon-cache -f -t /usr/share/icons/hicolor/ 2>/dev/null || true
update-desktop-database /usr/share/applications/ 2>/dev/null || true
exit 0
POST
chmod 755 "${STAGING}/DEBIAN/postinst"

echo "==> Building .deb…"
dpkg-deb --build --root-owner-group "$STAGING" "$DEB_NAME"

echo ""
echo "==> Done: ${DEB_NAME}"
echo ""
echo "Install with:"
echo "  apt install -y ./${DEB_NAME}"
