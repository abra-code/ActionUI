//! Helpers shared by the modules that call into `actionui-sys`.

use std::ffi::{CStr, CString, c_char, c_int};
use std::io::Write;
use std::panic::{AssertUnwindSafe, catch_unwind};

use actionui_sys as sys;

use crate::error::{Error, Result};

unsafe extern "C" {
    fn pthread_main_np() -> c_int;
    fn uuid_generate_random(out: *mut u8);
    fn uuid_unparse_upper(uuid: *const u8, out: *mut c_char);
}

pub(crate) fn is_main_thread() -> bool {
    unsafe { pthread_main_np() != 0 }
}

/// ActionUI keeps one last-error value for the whole process and gives its handlers no
/// thread guarantees beyond "main thread". Keeping every call on the main thread makes
/// error text reliable and rules out a worker waiting on a main thread that waits on it.
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

pub(crate) fn new_uuid() -> String {
    let mut bytes = [0u8; 16];
    // 36 characters and the terminating zero.
    let mut text = [0 as c_char; 37];
    unsafe {
        uuid_generate_random(bytes.as_mut_ptr());
        uuid_unparse_upper(bytes.as_ptr(), text.as_mut_ptr());
        CStr::from_ptr(text.as_ptr()).to_string_lossy().into_owned()
    }
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
