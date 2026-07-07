# NVIDIA Driver Installer

A GTK4 + libadwaita desktop app for installing NVIDIA drivers from official `.run` files on Linux — written in Rust.

Installs the new driver **repo-style**: the driver and DKMS module go on disk while your current driver keeps running, and the switch happens at your next reboot. No session teardown, no black screens, no dropping to a TTY.

## Features

- **Browse every driver version** NVIDIA has published, live from `download.nvidia.com`, with labels showing which is currently installed, which are upgrades, and which are older
- **System tab** — GPU model, running driver, kernel, DKMS module status, Secure Boot state, free disk space, and whether a reboot is pending
- **Reboot detection that actually works** — compares the on-disk kernel module (`modinfo`) against the running driver, so a pending install shows "Reboot Required: Yes" until you restart
- **SHA256 verification** of downloads against NVIDIA's published checksums, streamed in 1 MiB chunks
- **Download manager** — progress, speed, ETA, cancel support, retry with backoff
- **Local file support** — already have a `.run` file (e.g. a Vulkan beta driver)? Open it directly
- **DKMS integration** — kernel module rebuilds automatically on kernel updates
- **Safe by design** — the installer verifies the `.run` archive's integrity *before* touching anything, and the old driver is never disturbed while running
- **Single privileged step** — the GUI runs unprivileged; only the install script runs as root, authorized through polkit

## Installing

### AppImage (any distro)

Download the latest `.AppImage` from [Releases](../../releases), then:

```bash
chmod +x NVIDIA_Driver_Installer-*.AppImage
./NVIDIA_Driver_Installer-*.AppImage
```

First launch prompts once for your password to install the privileged helper and polkit policy. Every run after that is instant.

### .deb (Ubuntu / Debian)

Download the `.deb` from [Releases](../../releases), then:

```bash
sudo apt install -y ./nvidia-driver-installer_*.deb
```

This adds the app to your launcher with full desktop integration.

### Headless servers — no GUI needed

The privileged script is standalone bash. Copy `scripts/privileged-install.sh` to the server and run:

```bash
wget https://download.nvidia.com/XFree86/Linux-x86_64/<VERSION>/NVIDIA-Linux-x86_64-<VERSION>.run
sudo ./privileged-install.sh ./NVIDIA-Linux-x86_64-<VERSION>.run --dkms
```

Reboot to switch to the new driver. Logs go to `/var/log/nvidia-driver-installer.log`.

## Building from source

Requires Ubuntu 24.04+ (or equivalent) with `cargo`, `rustc`, `libgtk-4-dev`, `libadwaita-1-dev`, `pkg-config`, `libssl-dev`.

```bash
# .deb package
sudo bash build.sh

# AppImage
sudo bash build-appimage.sh
```

Both scripts install their own build dependencies via apt, compile the release binary, and produce the final artifact in the project directory.

## How it works

1. The GUI (unprivileged) scrapes NVIDIA's public archive for available versions, downloads the selected `.run`, and verifies its SHA256.
2. Clicking **Install Driver** invokes `privileged-install.sh` through `pkexec`, authorized by a polkit policy.
3. The script verifies the archive integrity (`--check`), ensures kernel headers and DKMS are present, clears any conflicting distro packages, writes the nouveau blacklist, and then runs NVIDIA's installer with `--allow-installation-with-running-driver` — the flag that makes it proceed exactly like a package-manager driver upgrade.
4. The new driver sits on disk; the running driver is untouched. Reboot whenever convenient, and the new one takes over.

## Options

| Option | Effect |
|---|---|
| Enable DKMS | Kernel module rebuilds automatically on kernel updates (recommended) |
| Hold Package Version | Pins any driver-related apt packages with `apt-mark hold` |
| Skip X Server Check | Passes `--no-x-check` to the installer (already the default behavior) |

## License

MIT — see [LICENSE](LICENSE).

## Author

Linnard Alex Brown Jr.
