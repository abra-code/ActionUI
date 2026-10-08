//! ActionUI's log: reading it and writing to it.

use std::ffi::{CStr, c_char};
use std::sync::{Arc, RwLock};

use actionui_sys as sys;

use crate::error::Result;
use crate::ffi;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum LogLevel {
    Error = 1,
    Warning = 2,
    Info = 3,
    Debug = 4,
    Verbose = 5,
}

impl LogLevel {
    fn from_raw(level: sys::ActionUILogLevel) -> LogLevel {
        match level {
            sys::ACTIONUI_LOG_LEVEL_ERROR => LogLevel::Error,
            sys::ACTIONUI_LOG_LEVEL_WARNING => LogLevel::Warning,
            sys::ACTIONUI_LOG_LEVEL_DEBUG => LogLevel::Debug,
            sys::ACTIONUI_LOG_LEVEL_VERBOSE => LogLevel::Verbose,
            _ => LogLevel::Info,
        }
    }
}

type Logger = Arc<dyn Fn(&str, LogLevel) + Send + Sync + 'static>;

static LOGGER: RwLock<Option<Logger>> = RwLock::new(None);

unsafe extern "C" fn logger_trampoline(message: *const c_char, level: sys::ActionUILogLevel) {
    if message.is_null() {
        return;
    }
    // Clone the logger out so it is not called with the lock held; a logger that sets a
    // new logger would otherwise deadlock.
    let logger = LOGGER.read().ok().and_then(|slot| slot.clone());
    let Some(logger) = logger else {
        return;
    };
    let text = unsafe { CStr::from_ptr(message) }.to_string_lossy();
    // Not reported through the log on a panic: that would call this function again.
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| logger(&text, LogLevel::from_raw(level))));
}

/// Sends every ActionUI log message to `logger`, in place of ActionUI's default logger.
/// The logger can be called on any thread.
pub fn set_logger(logger: impl Fn(&str, LogLevel) + Send + Sync + 'static) {
    // The old logger is dropped after the lock is released: dropping it runs the
    // destructors of what it captured, and one that logs would wait on this lock.
    let old = LOGGER.write().ok().and_then(|mut slot| slot.replace(Arc::new(logger)));
    drop(old);
    unsafe { sys::actionUISetLogger(Some(logger_trampoline)) };
}

/// Writes a message to ActionUI's log, from any thread.
pub fn log(level: LogLevel, message: &str) -> Result<()> {
    let message = ffi::cstring("log message", message)?;
    unsafe { sys::actionUILog(message.as_ptr(), level as sys::ActionUILogLevel) };
    Ok(())
}
