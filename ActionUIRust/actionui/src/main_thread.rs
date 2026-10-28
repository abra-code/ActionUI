//! Getting work onto the main thread.
//!
//! The main thread belongs to the application's event loop, and the [`crate::App`] exists
//! only there. A worker thread can use a [`crate::Window`] directly; for anything that
//! needs the `App` (a panel, a new window, a handler) it hands a closure to [`dispatch`].

use std::ffi::c_void;
#[cfg(target_os = "linux")]
use std::ffi::c_int;

use crate::ffi;

// The main queue is this exported object; the C header's dispatch_get_main_queue() is a
// macro that takes its address.
#[cfg(target_os = "macos")]
unsafe extern "C" {
    static _dispatch_main_q: c_void;
    fn dispatch_async_f(queue: *const c_void, context: *mut c_void, work: unsafe extern "C" fn(*mut c_void));
}

// On Linux, libActionUI.so keeps its libdispatch to itself, and GTK's main loop is GLib's:
// the work goes to a GLib source on the default main context, at the priority of the
// source that runs ActionUI's main queue there. libActionUI.so already needs GLib; the
// versioned name links it without its development files.
#[cfg(target_os = "linux")]
#[link(name = "libglib-2.0.so.0", kind = "dylib", modifiers = "+verbatim")]
unsafe extern "C" {
    fn g_idle_add_full(
        priority: c_int,
        function: unsafe extern "C" fn(*mut c_void) -> c_int,
        data: *mut c_void,
        notify: Option<unsafe extern "C" fn(*mut c_void)>,
    ) -> u32;
}

// G_PRIORITY_DEFAULT and G_SOURCE_REMOVE.
#[cfg(target_os = "linux")]
const G_PRIORITY_DEFAULT: c_int = 0;
#[cfg(target_os = "linux")]
const G_SOURCE_REMOVE: c_int = 0;

type Work = Box<dyn FnOnce() + Send + 'static>;

unsafe extern "C" fn run_work(context: *mut c_void) {
    let work = unsafe { Box::from_raw(context.cast::<Work>()) };
    ffi::guard("main-thread closure", (), move || work());
}

#[cfg(target_os = "linux")]
unsafe extern "C" fn run_work_once(context: *mut c_void) -> c_int {
    unsafe { run_work(context) };
    G_SOURCE_REMOVE
}

/// True on the thread the application's event loop runs on.
pub fn is_main_thread() -> bool {
    ffi::is_main_thread()
}

/// Runs `work` on the main thread, later, and returns at once. Callable from any thread,
/// the main thread included. Closures run in the order they were dispatched, once the
/// event loop is running ([`crate::App::run`]). On macOS they share one queue with what
/// ActionUI itself queues for the main thread (a [`crate::Window`] setter called on a
/// worker), so a closure dispatched after such a setter sees its value; on Linux the two
/// are separate sources of GLib's main loop and that order is not guaranteed.
pub fn dispatch(work: impl FnOnce() + Send + 'static) {
    let work: Box<Work> = Box::new(Box::new(work));
    #[cfg(target_os = "macos")]
    unsafe {
        dispatch_async_f(&raw const _dispatch_main_q, Box::into_raw(work).cast(), run_work);
    }
    #[cfg(target_os = "linux")]
    unsafe {
        g_idle_add_full(G_PRIORITY_DEFAULT, run_work_once, Box::into_raw(work).cast(), None);
    }
}
