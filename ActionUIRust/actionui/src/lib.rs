// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

//! Native macOS user interfaces described in JSON and driven from Rust, through ActionUI.
//!
//! The interface (windows, controls, the menu bar) is ActionUI JSON. The program reacts
//! to named actions and reads and writes element values by their integer IDs.
//!
//! ```no_run
//! use actionui::App;
//!
//! const NAME_FIELD: i64 = 1;
//! const GREETING: i64 = 2;
//!
//! fn main() -> actionui::Result<()> {
//!     let app = App::new()?;
//!     app.set_name("Greeter")?;
//!     let window = app.present_window_from_file("Greeter.json", None)?;
//!
//!     app.on_action("greet", move |_action| {
//!         let name = window.get_string(NAME_FIELD).ok().flatten().unwrap_or_default();
//!         let _ = window.set_string(GREETING, &format!("Hello, {name}!"));
//!     });
//!
//!     app.run()
//! }
//! ```
//!
//! # Threads
//!
//! Everything here runs on the main thread, which [`App::run`] hands to the event loop.
//! Calls from another thread return [`Error::NotMainThread`]. A worker thread passes its
//! result to the interface with [`main_thread::dispatch`]; a [`Window`] can be moved into
//! that closure. Never make the main thread wait for a worker.
//!
//! # Panics
//!
//! A panic in a handler is caught and written to standard error and to ActionUI's log,
//! and the application keeps running.

#[cfg(not(target_os = "macos"))]
compile_error!(
    "the actionui crate supports macOS only; put the dependency under \
     [target.'cfg(target_os = \"macos\")'.dependencies]"
);

#[cfg(target_os = "macos")]
mod app;
#[cfg(target_os = "macos")]
mod error;
#[cfg(target_os = "macos")]
mod ffi;
#[cfg(target_os = "macos")]
pub mod log;
#[cfg(target_os = "macos")]
pub mod main_thread;
#[cfg(target_os = "macos")]
mod window;

#[cfg(target_os = "macos")]
pub use app::{ActionContext, App};
#[cfg(target_os = "macos")]
pub use error::{Error, Result};
#[cfg(target_os = "macos")]
pub use log::LogLevel;
#[cfg(target_os = "macos")]
pub use window::{ContentSizeLimits, Window};

/// The version of the ActionUI frameworks linked into this program.
#[cfg(target_os = "macos")]
pub fn version() -> String {
    unsafe { ffi::take_string(actionui_sys::actionUIGetVersion()) }.unwrap_or_default()
}
