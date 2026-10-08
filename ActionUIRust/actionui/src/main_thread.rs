//! Getting work onto the main thread.
//!
//! The main thread belongs to the application's event loop, and the [`crate::App`] exists
//! only there. A worker thread can use a [`crate::Window`] directly; for anything that
//! needs the `App` (a panel, a new window, a handler) it hands a closure to [`dispatch`].

use std::ffi::c_void;

use crate::ffi;

// The main queue is this exported object; the C header's dispatch_get_main_queue() is a
// macro that takes its address.
unsafe extern "C" {
    static _dispatch_main_q: c_void;
    fn dispatch_async_f(queue: *const c_void, context: *mut c_void, work: unsafe extern "C" fn(*mut c_void));
}

type Work = Box<dyn FnOnce() + Send + 'static>;

unsafe extern "C" fn run_work(context: *mut c_void) {
    let work = unsafe { Box::from_raw(context.cast::<Work>()) };
    ffi::guard("main-thread closure", (), move || work());
}

/// True on the thread the application's event loop runs on.
pub fn is_main_thread() -> bool {
    ffi::is_main_thread()
}

/// Runs `work` on the main thread, later, and returns at once. Callable from any thread,
/// the main thread included. Closures run in the order they were dispatched, once the
/// event loop is running ([`crate::App::run`]).
pub fn dispatch(work: impl FnOnce() + Send + 'static) {
    let work: Box<Work> = Box::new(Box::new(work));
    unsafe {
        dispatch_async_f(&raw const _dispatch_main_q, Box::into_raw(work).cast(), run_work);
    }
}
