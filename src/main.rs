mod download;
mod install;
mod system;
mod ui;
mod versions;

use gtk4::prelude::*;
use std::sync::OnceLock;
use tokio::runtime::Runtime;

static TOKIO_RT: OnceLock<Runtime> = OnceLock::new();

pub fn runtime() -> &'static Runtime {
    TOKIO_RT.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("Failed to build Tokio runtime")
    })
}

fn main() {
    let _ = runtime();

    // Set program name before GTK init — this becomes WM_CLASS on X11/Wayland
    // and must match StartupWMClass in the .desktop file so GNOME groups the
    // window with the dock icon instead of showing two separate entries.
    glib::set_prgname(Some("nvidia-driver-installer"));
    glib::set_application_name("NVIDIA Driver Installer");

    let app = libadwaita::Application::builder()
        .application_id("io.github.labj1987.NVI")
        .flags(gio::ApplicationFlags::FLAGS_NONE)
        .build();

    app.connect_activate(|app| {
        if let Some(window) = app.windows().first() {
            window.present();
            return;
        }
        ui::build_ui(app);
    });

    std::process::exit(app.run().value());
}
