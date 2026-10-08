// Proves the static frameworks link and a call reaches them. Needs no window.

#![cfg(target_os = "macos")]

use std::ffi::CStr;

#[test]
fn version_is_reported() {
    let version = unsafe { actionui_sys::actionUIGetVersion() };
    assert!(!version.is_null(), "actionUIGetVersion returned null");
    let text = unsafe { CStr::from_ptr(version) }.to_string_lossy().into_owned();
    unsafe { actionui_sys::actionUIFreeString(version) };
    assert!(
        text.chars().next().is_some_and(|c| c.is_ascii_digit()),
        "unexpected version text: {text:?}"
    );
}
