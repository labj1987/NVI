# NVI — NVIDIA Driver Installer

GTK4 + libadwaita GUI, written in Rust, for browsing and installing
official NVIDIA `.run` drivers from download.nvidia.com. Distributed as
a single AppImage — **AppImage-only; no `.deb` packaging should ever be
reintroduced** (it was deliberately removed, along with the DBus service
file, when the app moved to the `io.github.labj1987.NVI` application ID).

Install model is repo-style: the new driver goes to disk while the
current one keeps running (`--allow-installation-with-running-driver`),
and the switch happens at the next reboot — no session teardown, no
black screens.

## Module layout (`src/`)

- `main.rs` — entry point, sets up the shared Tokio runtime and wires up
  the GTK application.
- `ui.rs` — the GTK4/libadwaita UI: browse/configure/install/system tabs.
- `versions.rs` — talks to download.nvidia.com/XFree86/Linux-x86_64/:
  lists available driver versions, fetches the SHA256 checksum for a
  version.
- `download.rs` — downloads the `.run` file with progress, cancel,
  retries, and SHA256 verification.
- `system.rs` — queries the local system: GPU, installed driver, kernel,
  DKMS status, Secure Boot state, free disk space, reboot-required state.
- `install.rs` — invokes `scripts/privileged-install.sh` via `pkexec`
  with `InstallOptions` (DKMS, version hold, etc).

## Build process

`build-appimage.sh` builds the AppImage — **unlike MKI, this uses
`linuxdeploy` + the GTK plugin, not `appimagetool` directly**:
1. Installs build deps via apt (cargo, rustc, gtk4/adwaita dev headers,
   `wget`, `zsync`), plus `libfuse2`/`libfuse2t64` best-effort.
2. `cargo build --release`.
3. Assembles the AppDir (binary, privileged script, polkit policy,
   appdata, desktop file, icon, generated `AppRun`).
4. Downloads `linuxdeploy` (continuous build) + the linuxdeploy-plugin-gtk
   script, and runs linuxdeploy with `UPDATE_INFORMATION` set for
   `gh-releases-zsync` delta updates.
5. Renames whatever linuxdeploy/appimagetool named the output file to
   `nvidia-driver-installer-$VERSION-x86_64.AppImage`.

**Gotcha (fixed in v2.5.6):** step 5's rename only covered the
`.AppImage` file. linuxdeploy/appimagetool can also produce a same-named
`.zsync` sidecar under the *original* (un-versioned) output filename —
that file was never renamed or moved, so it sat orphaned on disk under
a filename CI's release-asset glob doesn't match, and the `.zsync` never
got uploaded even when it was successfully generated. The rename step
now explicitly moves `OUTFILE.zsync` →
`nvidia-driver-installer-$VERSION-x86_64.AppImage.zsync` right after the
AppImage rename, if it exists. When touching the OUTFILE rename logic
again, remember there are two files to rename, not one.

## Release process

1. Bump `version` in `Cargo.toml`.
2. Add a `CHANGELOG.md` entry.
3. Commit, push to `main`.
4. `git tag vX.Y.Z && git push origin vX.Y.Z`.
5. The tag push triggers `.github/workflows/release.yml` ("Build and
   Release"), which runs `build-appimage.sh` and uploads the AppImage
   (+ `.zsync`) to a GitHub Release via `softprops/action-gh-release`.
   The release-asset glob must match both files — check it whenever the
   output filename pattern changes.

## Conventions

- Don't use `sed`/`awk` to edit files — use direct file writes/edits.
  `tee` is fine for one-off terminal inspection, but Claude Code sessions
  should edit files directly rather than shelling through it.
- Repo lives at `/home/alex/NVI`, owned by user `alex` — if operating as
  root, run git commands as `alex` (`su -s /bin/bash alex -c '...'`) to
  keep authorship and file ownership correct.
