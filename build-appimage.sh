#!/usr/bin/env bash
# build-appimage.sh — Build nvidia-driver-installer as an AppImage
# Run from the project root on LordNikon (Ubuntu 26.04, amd64)
set -euo pipefail

APP="nvidia-driver-installer"
VERSION="2.4.0"
APPDIR="$(pwd)/AppDir"

echo "==> Checking build dependencies…"
apt-get install -y \
    cargo \
    rustc \
    libgtk-4-dev \
    libadwaita-1-dev \
    pkg-config \
    libssl-dev \
    wget

# FUSE is only needed to RUN the finished AppImage, not to build it
# (linuxdeploy runs with APPIMAGE_EXTRACT_AND_RUN=1). The package name
# changed to libfuse2t64 on newer Ubuntu, so try both and never fail
# the build over it.
apt-get install -y libfuse2 2>/dev/null \
    || apt-get install -y libfuse2t64 2>/dev/null \
    || echo "NOTE: libfuse2 not available — run the AppImage with --appimage-extract-and-run"

echo "==> Building release binary…"
cargo build --release

echo "==> Setting up AppDir…"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin"
mkdir -p "$APPDIR/usr/lib/${APP}"
mkdir -p "$APPDIR/usr/share/applications"
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$APPDIR/usr/share/polkit-1/actions"

# Binary
install -Dm755 "target/release/${APP}" "$APPDIR/usr/bin/${APP}"

# Privileged install script — stays bundled, extracted at runtime
install -Dm755 "scripts/privileged-install.sh" \
    "$APPDIR/usr/lib/${APP}/privileged-install.sh"

# Polkit policy
install -Dm644 "data/com.lordnikon.nvidia-driver-installer.policy" \
    "$APPDIR/usr/share/polkit-1/actions/com.lordnikon.nvidia-driver-installer.policy"

# Desktop file — AppImage-specific copy WITHOUT DBusActivatable.
# DBus activation needs a system-installed service file pointing at a
# real /usr/bin binary, which AppImage users don't have; leaving the key
# in would make an integrated dock icon silently do nothing. Runtime
# single-instance behaviour still works (GApplication claims the bus
# name itself when the app starts).
sed '/^DBusActivatable=/d' "data/nvidia-driver-installer.desktop" \
    > "$APPDIR/nvidia-driver-installer.desktop"
install -Dm644 "$APPDIR/nvidia-driver-installer.desktop" \
    "$APPDIR/usr/share/applications/nvidia-driver-installer.desktop"

# Icon (256px for AppImage standard)
install -Dm644 "data/nvidia-driver-installer-256.png" \
    "$APPDIR/usr/share/icons/hicolor/256x256/apps/nvidia-driver-installer.png"
# AppImage also wants icon at root of AppDir
cp "data/nvidia-driver-installer-256.png" "$APPDIR/nvidia-driver-installer.png"

# AppRun — the entry point for the AppImage
# root (via pkexec) cannot read files out of this user's FUSE-mounted
# AppImage, so the privileged files are staged to /tmp before being
# installed to their real system locations.
cat > "$APPDIR/AppRun" << 'APPRUN'
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "$0")")"

# The privileged helper must live on the real filesystem: pkexec cannot
# execute anything under the AppImage's FUSE mount. Install it and the
# polkit policy on first run, and REFRESH them if the bundled copies
# differ (i.e. after updating to a newer AppImage).
PRIV_SRC="${HERE}/usr/lib/nvidia-driver-installer/privileged-install.sh"
PRIV_DST="/usr/lib/nvidia-driver-installer/privileged-install.sh"
POLICY_SRC="${HERE}/usr/share/polkit-1/actions/com.lordnikon.nvidia-driver-installer.policy"
POLICY_DST="/usr/share/polkit-1/actions/com.lordnikon.nvidia-driver-installer.policy"

need_install=0
[[ -f "$PRIV_DST" ]]   || need_install=1
[[ -f "$POLICY_DST" ]] || need_install=1
if [[ $need_install -eq 0 ]]; then
    cmp -s "$PRIV_SRC" "$PRIV_DST"     || need_install=1
    cmp -s "$POLICY_SRC" "$POLICY_DST" || need_install=1
fi

if [[ $need_install -eq 1 ]]; then
    echo "Installing/updating privileged components (password required)…"

    # pkexec elevates to root, but root cannot read files out of THIS
    # user's FUSE mount (AppImages are only readable by the mounting
    # user). Stage the two small files in /tmp first — root can read
    # /tmp — then have the privileged install copy from there instead
    # of reaching back into the mount.
    STAGE="$(mktemp -d /tmp/nvidia-driver-installer.XXXXXX)"
    cp "$PRIV_SRC" "$STAGE/privileged-install.sh"
    cp "$POLICY_SRC" "$STAGE/policy.policy"
    chmod 644 "$STAGE"/*

    pkexec bash -c "
        install -Dm755 '${STAGE}/privileged-install.sh' '${PRIV_DST}'
        install -Dm644 '${STAGE}/policy.policy' '${POLICY_DST}'
    "
    STATUS=$?

    rm -rf "$STAGE"

    if [[ $STATUS -ne 0 ]]; then
        echo "Failed to install privileged components (exit $STATUS)." >&2
        echo "The app will still open, but Install Driver will not work" >&2
        echo "until this succeeds. Try running the AppImage again." >&2
    fi
fi

# Run the app
export PATH="${HERE}/usr/bin:$PATH"
export XDG_DATA_DIRS="${HERE}/usr/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
exec "${HERE}/usr/bin/nvidia-driver-installer" "$@"
APPRUN
chmod +x "$APPDIR/AppRun"

echo "==> Downloading linuxdeploy and GTK plugin…"
wget -q -c "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage" \
    -O linuxdeploy-x86_64.AppImage
wget -q -c "https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/master/linuxdeploy-plugin-gtk.sh"
chmod +x linuxdeploy-x86_64.AppImage linuxdeploy-plugin-gtk.sh

echo "==> Building AppImage…"
APPIMAGE_EXTRACT_AND_RUN=1 \
VERSION="$VERSION" \
    ./linuxdeploy-x86_64.AppImage \
    --appdir "$APPDIR" \
    --plugin gtk \
    --output appimage \
    --icon-file "data/nvidia-driver-installer-256.png" \
    --desktop-file "$APPDIR/nvidia-driver-installer.desktop"

# Rename to something clean
OUTFILE=$(ls *.AppImage 2>/dev/null | head -1)
if [[ -n "$OUTFILE" ]]; then
    mv "$OUTFILE" "nvidia-driver-installer-${VERSION}-x86_64.AppImage"
    chmod +x "nvidia-driver-installer-${VERSION}-x86_64.AppImage"
    echo ""
    echo "==> Done: nvidia-driver-installer-${VERSION}-x86_64.AppImage"
    echo ""
    echo "Users can run it with:"
    echo "  chmod +x nvidia-driver-installer-${VERSION}-x86_64.AppImage"
    echo "  ./nvidia-driver-installer-${VERSION}-x86_64.AppImage"
fi
