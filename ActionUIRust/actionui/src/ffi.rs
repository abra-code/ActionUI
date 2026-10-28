//! Helpers shared by the modules that call into `actionui-sys`.

use std::ffi::{CStr, CString, c_char, c_int, c_void};
use std::io::Write;
use std::panic::{AssertUnwindSafe, catch_unwind};

use actionui_sys as sys;

use crate::error::{Error, Result};

unsafe extern "C" {
    fn getentropy(buffer: *mut c_void, length: usize) -> c_int;
}

#[cfg(target_os = "macos")]
unsafe extern "C" {
    fn pthread_main_np() -> c_int;
}

#[cfg(target_os = "linux")]
unsafe extern "C" {
    fn gettid() -> c_int;
    fn getpid() -> c_int;
}

#[cfg(target_os = "macos")]
pub(crate) fn is_main_thread() -> bool {
    unsafe { pthread_main_np() != 0 }
}

/// The main thread's ID is the process ID. It is also the thread ActionUI takes for the
/// main one: the program loads libActionUI.so on it, at startup.
#[cfg(target_os = "linux")]
pub(crate) fn is_main_thread() -> bool {
    unsafe { gettid() == getpid() }
}

/// For what exists only on the main thread: the application, and the handlers, whose
/// tables ActionUI keeps without any locking.
pub(crate) fn require_main_thread() -> Result<()> {
    if is_main_thread() { Ok(()) } else { Err(Error::NotMainThread) }
}

/// `what` names the string in the error message, for example "window title".
pub(crate) fn cstring(what: &'static str, text: &str) -> Result<CString> {
    CString::new(text).map_err(|_| Error::InteriorNul(what))
}

pub(crate) fn optional_cstring(what: &'static str, text: Option<&str>) -> Result<Option<CString>> {
    text.map(|text| cstring(what, text)).transpose()
}

pub(crate) fn optional_ptr(text: &Option<CString>) -> *const c_char {
    text.as_ref().map_or(std::ptr::null(), |text| text.as_ptr())
}

/// Copies a string ActionUI allocated and releases the original. Null gives `None`.
///
/// # Safety
/// `pointer` must be null or a string returned by an ActionUI function that hands
/// ownership to the caller, not yet released.
pub(crate) unsafe fn take_string(pointer: *mut c_char) -> Option<String> {
    if pointer.is_null() {
        return None;
    }
    let text = unsafe { CStr::from_ptr(pointer) }.to_string_lossy().into_owned();
    unsafe { sys::actionUIFreeString(pointer) };
    Some(text)
}

/// Copies a string ActionUI still owns. Null gives `None`.
///
/// # Safety
/// `pointer` must be null or a valid null-terminated string.
pub(crate) unsafe fn copy_string(pointer: *const c_char) -> Option<String> {
    if pointer.is_null() {
        return None;
    }
    Some(unsafe { CStr::from_ptr(pointer) }.to_string_lossy().into_owned())
}

pub(crate) fn last_error() -> Option<String> {
    unsafe { take_string(sys::actionUIGetLastError()) }
}

/// For a call that reported failure: ActionUI's own message, or `fallback` when it
/// recorded none.
pub(crate) fn failure(fallback: &str) -> Error {
    Error::ActionUI(last_error().unwrap_or_else(|| fallback.to_string()))
}

/// For a getter that returned nothing: an error if ActionUI recorded one, otherwise the
/// element simply has no value.
pub(crate) fn none_or_error<T>() -> Result<Option<T>> {
    match last_error() {
        Some(message) => Err(Error::ActionUI(message)),
        None => Ok(None),
    }
}

/// A random (version 4) UUID in upper case, as uuid_generate_random and uuid_unparse_upper
/// give it on macOS; Linux's C library has no uuid functions.
pub(crate) fn new_uuid() -> String {
    let mut bytes = [0u8; 16];
    let status = unsafe { getentropy(bytes.as_mut_ptr().cast(), bytes.len()) };
    // It fails only for more than 256 bytes or a bad buffer.
    assert_eq!(status, 0, "getentropy failed");
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    let mut text = String::with_capacity(36);
    for (index, byte) in bytes.iter().enumerate() {
        if matches!(index, 4 | 6 | 8 | 10) {
            text.push('-');
        }
        text.push_str(&format!("{byte:02X}"));
    }
    text
}

/// Runs a user callback on behalf of a C caller. A panic must not travel into Swift
/// (the process would abort), so it is caught, reported and replaced by `fallback`.
pub(crate) fn guard<R>(what: &str, fallback: R, callback: impl FnOnce() -> R) -> R {
    match catch_unwind(AssertUnwindSafe(callback)) {
        Ok(value) => value,
        Err(payload) => {
            let detail = payload
                .downcast_ref::<&str>()
                .map(|text| text.to_string())
                .or_else(|| payload.downcast_ref::<String>().cloned())
                .unwrap_or_else(|| "no message".to_string());
            let message = format!("A Rust {what} panicked: {detail}");
            // Not eprintln!: it panics when standard error cannot be written (a closed
            // pipe), and a panic here is outside catch_unwind.
            let _ = writeln!(std::io::stderr(), "{message}");
            if let Ok(message) = CString::new(message) {
                unsafe { sys::actionUILog(message.as_ptr(), sys::ACTIONUI_LOG_LEVEL_ERROR) };
            }
            fallback
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn interior_nul_is_an_error_not_a_panic() {
        assert!(matches!(cstring("title", "a\0b"), Err(Error::InteriorNul("title"))));
        assert!(cstring("title", "plain").is_ok());
    }

    #[test]
    fn uuids_are_distinct_and_well_formed() {
        let first = new_uuid();
        let second = new_uuid();
        assert_eq!(first.len(), 36);
        assert_eq!(first.matches('-').count(), 4);
        assert_ne!(first, second);
        // Version 4, the RFC 4122 variant, upper case.
        assert_eq!(&first[14..15], "4");
        assert!(matches!(&first[19..20], "8" | "9" | "A" | "B"));
        assert_eq!(first, first.to_uppercase());
    }

    #[test]
    fn guard_contains_a_panic() {
        let value = guard("test callback", 7, || -> i32 { panic!("expected in this test") });
        assert_eq!(value, 7);
        assert_eq!(guard("test callback", 0, || 3), 3);
    }

    #[test]
    fn a_test_thread_is_not_the_main_thread() {
        assert!(matches!(require_main_thread(), Err(Error::NotMainThread)));
    }
}
