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
/// are separate sources of GLib's main loop and that order is not guaranteed. On Android they
/// run on the app's main Looper, after the first HostSurface delegate was bound (which
/// attaches this crate to it); closures dispatched before that wait for it.
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
    #[cfg(target_os = "android")]
    looper::post(work);
}

/// Android: the main Looper wakes for a pipe this crate writes a byte into when work is queued.
#[cfg(target_os = "android")]
pub(crate) mod looper {
    use std::collections::VecDeque;
    use std::ffi::{c_int, c_void};
    use std::sync::Mutex;
    use std::sync::atomic::{AtomicI32, Ordering};

    use super::{Work, run_work};

    #[link(name = "android")]
    unsafe extern "C" {
        fn ALooper_forThread() -> *mut c_void;
        fn ALooper_addFd(
            looper: *mut c_void,
            fd: c_int,
            ident: c_int,
            events: c_int,
            callback: Option<unsafe extern "C" fn(c_int, c_int, *mut c_void) -> c_int>,
            data: *mut c_void,
        ) -> c_int;
    }

    unsafe extern "C" {
        fn pipe2(fds: *mut c_int, flags: c_int) -> c_int;
        fn read(fd: c_int, buffer: *mut c_void, count: usize) -> isize;
        fn write(fd: c_int, buffer: *const c_void, count: usize) -> isize;
        fn close(fd: c_int) -> c_int;
    }

    // <android/looper.h> and <fcntl.h> (the same values on every Android ABI).
    const ALOOPER_POLL_CALLBACK: c_int = -2;
    const ALOOPER_EVENT_INPUT: c_int = 1;
    const O_NONBLOCK: c_int = 0o4000;
    const O_CLOEXEC: c_int = 0o2000000;

    static QUEUE: Mutex<VecDeque<Box<Work>>> = Mutex::new(VecDeque::new());
    /// The pipe's write end once attached; -1 before.
    static WAKE_FD: AtomicI32 = AtomicI32::new(-1);

    /// Attaches to the calling thread's Looper (the main one: called from a main-thread-only
    /// function). Once; true when attached.
    pub(crate) fn attach() -> bool {
        if WAKE_FD.load(Ordering::Acquire) >= 0 {
            return true;
        }
        let looper = unsafe { ALooper_forThread() };
        if looper.is_null() {
            return false;
        }
        let mut fds = [0 as c_int; 2];
        if unsafe { pipe2(fds.as_mut_ptr(), O_NONBLOCK | O_CLOEXEC) } != 0 {
            return false;
        }
        let added = unsafe {
            ALooper_addFd(looper, fds[0], ALOOPER_POLL_CALLBACK, ALOOPER_EVENT_INPUT, Some(drain), std::ptr::null_mut())
        };
        if added != 1 {
            unsafe {
                close(fds[0]);
                close(fds[1]);
            }
            return false;
        }
        WAKE_FD.store(fds[1], Ordering::Release);
        // Work queued before the attach.
        wake();
        true
    }

    pub(crate) fn post(work: Box<Work>) {
        QUEUE.lock().unwrap_or_else(|poisoned| poisoned.into_inner()).push_back(work);
        wake();
    }

    fn wake() {
        let fd = WAKE_FD.load(Ordering::Acquire);
        if fd >= 0 {
            let byte = 1u8;
            // A full pipe (EAGAIN) already has the Looper woken.
            let _ = unsafe { write(fd, (&raw const byte).cast(), 1) };
        }
    }

    /// On the main Looper: empties the pipe, then runs the work queued so far, in order. Work
    /// that a closure queues runs on a later Looper turn (it has written a byte of its own), as
    /// on macOS and Linux: a closure that dispatches itself again does not hold the Looper.
    unsafe extern "C" fn drain(fd: c_int, _events: c_int, _data: *mut c_void) -> c_int {
        let mut buffer = [0u8; 64];
        while unsafe { read(fd, buffer.as_mut_ptr().cast(), buffer.len()) } > 0 {}
        let batch = std::mem::take(&mut *QUEUE.lock().unwrap_or_else(|poisoned| poisoned.into_inner()));
        for work in batch {
            unsafe { run_work(Box::into_raw(work).cast()) };
        }
        // Keep the callback.
        1
    }
}
