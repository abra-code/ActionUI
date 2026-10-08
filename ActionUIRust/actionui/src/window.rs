//! A window and the values of the elements in it.

use std::ffi::CString;
use std::sync::Arc;

use actionui_sys as sys;
use serde::Serialize;
use serde::de::DeserializeOwned;

use crate::error::Result;
use crate::ffi;

/// The smallest and largest size a window's content accepts, in points. A flexible axis
/// reports a very large maximum; equal minimum and maximum mean a fixed size.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ContentSizeLimits {
    pub min_width: f64,
    pub min_height: f64,
    pub max_width: f64,
    pub max_height: f64,
}

/// A handle to one window. It is only the window's identifier, so it is cheap to clone
/// and can be moved into closures and to other threads; the calls themselves have to be
/// made on the main thread and return [`crate::Error::NotMainThread`] anywhere else.
///
/// Elements are addressed by the integer `id` they have in the JSON. A few elements have
/// parts (a table column, for example); the `_part` methods address those, and the plain
/// methods address part 0, the element itself.
///
/// Setters return once the value is queued: an unknown view ID is reported in ActionUI's
/// log, not as an error here. Getters return `Ok(None)` when the element has no value.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Window {
    uuid: Arc<str>,
}

impl Window {
    pub(crate) fn with_uuid(uuid: &str) -> Window {
        Window { uuid: Arc::from(uuid) }
    }

    /// The identifier ActionUI knows this window by.
    pub fn uuid(&self) -> &str {
        &self.uuid
    }

    fn uuid_c(&self) -> Result<CString> {
        ffi::require_main_thread()?;
        ffi::cstring("window UUID", &self.uuid)
    }

    /// Closes the window. The handler set with [`crate::App::on_window_will_close`] runs
    /// first.
    pub fn close(&self) -> Result<()> {
        let uuid = self.uuid_c()?;
        unsafe { sys::actionUIAppCloseWindow(uuid.as_ptr()) };
        Ok(())
    }

    /// `None` until the window's content has been loaded.
    pub fn content_size_limits(&self) -> Result<Option<ContentSizeLimits>> {
        let uuid = self.uuid_c()?;
        let mut limits = ContentSizeLimits { min_width: 0.0, min_height: 0.0, max_width: 0.0, max_height: 0.0 };
        let found = unsafe {
            sys::actionUIGetContentSizeLimits(
                uuid.as_ptr(),
                &mut limits.min_width,
                &mut limits.min_height,
                &mut limits.max_width,
                &mut limits.max_height,
            )
        };
        Ok(found.then_some(limits))
    }

    // MARK: - Typed values

    pub fn set_string(&self, view_id: i64, value: &str) -> Result<()> {
        self.set_string_part(view_id, 0, value)
    }

    pub fn set_string_part(&self, view_id: i64, view_part_id: i64, value: &str) -> Result<()> {
        let uuid = self.uuid_c()?;
        let value = ffi::cstring("string value", value)?;
        let accepted = unsafe { sys::actionUISetStringValue(uuid.as_ptr(), view_id, view_part_id, value.as_ptr()) };
        if accepted { Ok(()) } else { Err(ffi::failure("ActionUI did not accept the string value")) }
    }

    pub fn set_int(&self, view_id: i64, value: i64) -> Result<()> {
        self.set_int_part(view_id, 0, value)
    }

    pub fn set_int_part(&self, view_id: i64, view_part_id: i64, value: i64) -> Result<()> {
        let uuid = self.uuid_c()?;
        let accepted = unsafe { sys::actionUISetIntValue(uuid.as_ptr(), view_id, view_part_id, value) };
        if accepted { Ok(()) } else { Err(ffi::failure("ActionUI did not accept the integer value")) }
    }

    pub fn set_double(&self, view_id: i64, value: f64) -> Result<()> {
        self.set_double_part(view_id, 0, value)
    }

    pub fn set_double_part(&self, view_id: i64, view_part_id: i64, value: f64) -> Result<()> {
        let uuid = self.uuid_c()?;
        let accepted = unsafe { sys::actionUISetDoubleValue(uuid.as_ptr(), view_id, view_part_id, value) };
        if accepted { Ok(()) } else { Err(ffi::failure("ActionUI did not accept the number value")) }
    }

    pub fn set_bool(&self, view_id: i64, value: bool) -> Result<()> {
        self.set_bool_part(view_id, 0, value)
    }

    pub fn set_bool_part(&self, view_id: i64, view_part_id: i64, value: bool) -> Result<()> {
        let uuid = self.uuid_c()?;
        let accepted = unsafe { sys::actionUISetBoolValue(uuid.as_ptr(), view_id, view_part_id, value) };
        if accepted { Ok(()) } else { Err(ffi::failure("ActionUI did not accept the boolean value")) }
    }

    /// An error when the element's value is not a string.
    pub fn get_string(&self, view_id: i64) -> Result<Option<String>> {
        self.get_string_part(view_id, 0)
    }

    pub fn get_string_part(&self, view_id: i64, view_part_id: i64) -> Result<Option<String>> {
        let uuid = self.uuid_c()?;
        let value = unsafe { ffi::take_string(sys::actionUIGetStringValue(uuid.as_ptr(), view_id, view_part_id)) };
        match value {
            Some(value) => Ok(Some(value)),
            None => ffi::none_or_error(),
        }
    }

    /// A number value with a fraction is truncated. An error when the value is not a number.
    pub fn get_int(&self, view_id: i64) -> Result<Option<i64>> {
        self.get_int_part(view_id, 0)
    }

    pub fn get_int_part(&self, view_id: i64, view_part_id: i64) -> Result<Option<i64>> {
        let uuid = self.uuid_c()?;
        let mut value = 0i64;
        let found = unsafe { sys::actionUIGetIntValue(uuid.as_ptr(), view_id, view_part_id, &mut value) };
        if found { Ok(Some(value)) } else { ffi::none_or_error() }
    }

    /// An error when the element's value is not a number.
    pub fn get_double(&self, view_id: i64) -> Result<Option<f64>> {
        self.get_double_part(view_id, 0)
    }

    pub fn get_double_part(&self, view_id: i64, view_part_id: i64) -> Result<Option<f64>> {
        let uuid = self.uuid_c()?;
        let mut value = 0f64;
        let found = unsafe { sys::actionUIGetDoubleValue(uuid.as_ptr(), view_id, view_part_id, &mut value) };
        if found { Ok(Some(value)) } else { ffi::none_or_error() }
    }

    /// An error when the element's value is not a boolean.
    pub fn get_bool(&self, view_id: i64) -> Result<Option<bool>> {
        self.get_bool_part(view_id, 0)
    }

    pub fn get_bool_part(&self, view_id: i64, view_part_id: i64) -> Result<Option<bool>> {
        let uuid = self.uuid_c()?;
        let mut value = false;
        let found = unsafe { sys::actionUIGetBoolValue(uuid.as_ptr(), view_id, view_part_id, &mut value) };
        if found { Ok(Some(value)) } else { ffi::none_or_error() }
    }

    // MARK: - Values of any shape

    /// Sets an element's value from anything that serializes to JSON: a string, a number,
    /// a list, a `serde_json::Value`, or a type of your own.
    pub fn set_value<T: Serialize + ?Sized>(&self, view_id: i64, value: &T) -> Result<()> {
        self.set_value_part(view_id, 0, value)
    }

    pub fn set_value_part<T: Serialize + ?Sized>(&self, view_id: i64, view_part_id: i64, value: &T) -> Result<()> {
        let uuid = self.uuid_c()?;
        let json = ffi::cstring("value JSON", &serde_json::to_string(value)?)?;
        let accepted = unsafe { sys::actionUISetElementValueJSON(uuid.as_ptr(), view_id, view_part_id, json.as_ptr()) };
        if accepted { Ok(()) } else { Err(ffi::failure("ActionUI did not accept the value")) }
    }

    /// Reads an element's value into any type that deserializes from JSON. Ask for
    /// `serde_json::Value` when the shape is not known in advance.
    pub fn get_value<T: DeserializeOwned>(&self, view_id: i64) -> Result<Option<T>> {
        self.get_value_part(view_id, 0)
    }

    pub fn get_value_part<T: DeserializeOwned>(&self, view_id: i64, view_part_id: i64) -> Result<Option<T>> {
        let uuid = self.uuid_c()?;
        let json = unsafe { ffi::take_string(sys::actionUIGetElementValueJSON(uuid.as_ptr(), view_id, view_part_id)) };
        match json {
            Some(json) => Ok(Some(serde_json::from_str(&json)?)),
            None => ffi::none_or_error(),
        }
    }
}
