//! A window and the values of the elements in it.

use std::collections::BTreeMap;
use std::ffi::CString;
use std::sync::Arc;
use std::time::Duration;

use actionui_sys as sys;
use serde::Serialize;
use serde::de::DeserializeOwned;

use crate::dialog::{DialogButton, InsertPosition, ModalStyle};
use crate::error::{Error, Result};
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
/// and can be moved into closures and to other threads.
///
/// The methods can be called from any thread; ActionUI moves each call to the main
/// thread. From another thread a setter returns at once and the change is applied later,
/// while a getter (and anything else that returns a result) waits for the main thread.
/// So the main thread must never wait for a worker that calls into a window: the two
/// would wait for each other forever.
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

// Values as text, table rows and selection, properties, state, and the element list.
impl Window {
    // MARK: - Values as text

    /// Sets an element's value from text, converted by the element to its own value type.
    /// `content_type` names the format of the text for elements that accept more than
    /// one; pass `None` for the element's default.
    pub fn set_value_from_string(&self, view_id: i64, value: &str, content_type: Option<&str>) -> Result<()> {
        self.set_value_from_string_part(view_id, 0, value, content_type)
    }

    pub fn set_value_from_string_part(&self, view_id: i64, view_part_id: i64, value: &str, content_type: Option<&str>) -> Result<()> {
        let uuid = self.uuid_c()?;
        let value = ffi::cstring("string value", value)?;
        let content_type = ffi::optional_cstring("content type", content_type)?;
        let accepted = unsafe {
            sys::actionUISetElementValueString(uuid.as_ptr(), view_id, view_part_id, value.as_ptr(), ffi::optional_ptr(&content_type))
        };
        if accepted { Ok(()) } else { Err(ffi::failure("ActionUI did not accept the value")) }
    }

    /// An element's value as text, whatever its own type is.
    pub fn get_value_as_string(&self, view_id: i64, content_type: Option<&str>) -> Result<Option<String>> {
        self.get_value_as_string_part(view_id, 0, content_type)
    }

    pub fn get_value_as_string_part(&self, view_id: i64, view_part_id: i64, content_type: Option<&str>) -> Result<Option<String>> {
        let uuid = self.uuid_c()?;
        let content_type = ffi::optional_cstring("content type", content_type)?;
        let value = unsafe {
            ffi::take_string(sys::actionUIGetElementValueString(uuid.as_ptr(), view_id, view_part_id, ffi::optional_ptr(&content_type)))
        };
        match value {
            Some(value) => Ok(Some(value)),
            None => ffi::none_or_error(),
        }
    }

    // MARK: - Rows of a Table or List

    /// The number of columns of a Table or List; 0 for any other element.
    pub fn column_count(&self, view_id: i64) -> Result<i64> {
        let uuid = self.uuid_c()?;
        Ok(unsafe { sys::actionUIGetElementColumnCount(uuid.as_ptr(), view_id) })
    }

    /// The rows of a Table or List, usually read as `Vec<Vec<String>>`: one list of cell
    /// texts per row. `None` when the element has no rows or is not a Table or List.
    pub fn get_rows<T: DeserializeOwned>(&self, view_id: i64) -> Result<Option<T>> {
        let uuid = self.uuid_c()?;
        let json = unsafe { ffi::take_string(sys::actionUIGetElementRowsJSON(uuid.as_ptr(), view_id)) };
        match json {
            Some(json) => Ok(Some(serde_json::from_str(&json)?)),
            None => ffi::none_or_error(),
        }
    }

    /// Replaces all rows. `rows` is anything that serializes to a list of rows, each a
    /// list of cells: `&[["a", "b"], ["c", "d"]]`, a `Vec<Vec<String>>`, and so on.
    pub fn set_rows<T: Serialize + ?Sized>(&self, view_id: i64, rows: &T) -> Result<()> {
        let uuid = self.uuid_c()?;
        let json = ffi::cstring("rows JSON", &serde_json::to_string(rows)?)?;
        let accepted = unsafe { sys::actionUISetElementRowsJSON(uuid.as_ptr(), view_id, json.as_ptr()) };
        if accepted { Ok(()) } else { Err(ffi::failure("ActionUI did not accept the rows")) }
    }

    /// Adds rows after the existing ones.
    pub fn append_rows<T: Serialize + ?Sized>(&self, view_id: i64, rows: &T) -> Result<()> {
        let uuid = self.uuid_c()?;
        let json = ffi::cstring("rows JSON", &serde_json::to_string(rows)?)?;
        let accepted = unsafe { sys::actionUIAppendElementRowsJSON(uuid.as_ptr(), view_id, json.as_ptr()) };
        if accepted { Ok(()) } else { Err(ffi::failure("ActionUI did not accept the rows")) }
    }

    pub fn clear_rows(&self, view_id: i64) -> Result<()> {
        let uuid = self.uuid_c()?;
        unsafe { sys::actionUIClearElementRows(uuid.as_ptr(), view_id) };
        Ok(())
    }

    /// Selects the row at a 0-based index and returns true. An index outside the rows
    /// clears the selection and returns false, as does an element that is not a Table or
    /// List. Selecting from code fires no action.
    pub fn select_row(&self, view_id: i64, index: i64) -> Result<bool> {
        let uuid = self.uuid_c()?;
        Ok(unsafe { sys::actionUISelectElementRowByIndex(uuid.as_ptr(), view_id, index) })
    }

    /// Selects the first row with a cell equal to `text` (exact, case-sensitive), looking
    /// in one 0-based column or, with `None`, in all of them. Returns the index of the
    /// selected row, or `None` when no row matched. Fires no action.
    pub fn select_row_with_content(&self, view_id: i64, text: &str, column: Option<i64>) -> Result<Option<i64>> {
        let uuid = self.uuid_c()?;
        let text = ffi::cstring("row text", text)?;
        let index = unsafe { sys::actionUISelectElementRowWithContent(uuid.as_ptr(), view_id, text.as_ptr(), column.unwrap_or(-1)) };
        Ok((index >= 0).then_some(index))
    }

    pub fn clear_selection(&self, view_id: i64) -> Result<()> {
        let uuid = self.uuid_c()?;
        unsafe { sys::actionUIClearElementSelection(uuid.as_ptr(), view_id) };
        Ok(())
    }

    // MARK: - Properties

    /// Reads one of the element's properties, the ones written under "properties" in the
    /// JSON (`"title"`, `"disabled"`, `"hidden"` and so on).
    pub fn get_property<T: DeserializeOwned>(&self, view_id: i64, name: &str) -> Result<Option<T>> {
        let uuid = self.uuid_c()?;
        let name = ffi::cstring("property name", name)?;
        let json = unsafe { ffi::take_string(sys::actionUIGetElementPropertyJSON(uuid.as_ptr(), view_id, name.as_ptr())) };
        match json {
            Some(json) => Ok(Some(serde_json::from_str(&json)?)),
            None => ffi::none_or_error(),
        }
    }

    /// Changes one of the element's properties. The new value is validated the same way
    /// as a value in the JSON.
    pub fn set_property<T: Serialize + ?Sized>(&self, view_id: i64, name: &str, value: &T) -> Result<()> {
        let uuid = self.uuid_c()?;
        let name = ffi::cstring("property name", name)?;
        let json = ffi::cstring("property JSON", &serde_json::to_string(value)?)?;
        let accepted = unsafe { sys::actionUISetElementPropertyJSON(uuid.as_ptr(), view_id, name.as_ptr(), json.as_ptr()) };
        if accepted { Ok(()) } else { Err(ffi::failure("ActionUI did not accept the property")) }
    }

    // MARK: - State

    /// Reads one item of an element's run-time state by its key.
    pub fn get_state<T: DeserializeOwned>(&self, view_id: i64, key: &str) -> Result<Option<T>> {
        let uuid = self.uuid_c()?;
        let key = ffi::cstring("state key", key)?;
        let json = unsafe { ffi::take_string(sys::actionUIGetElementStateJSON(uuid.as_ptr(), view_id, key.as_ptr())) };
        match json {
            Some(json) => Ok(Some(serde_json::from_str(&json)?)),
            None => ffi::none_or_error(),
        }
    }

    /// One item of an element's state as text.
    pub fn get_state_string(&self, view_id: i64, key: &str) -> Result<Option<String>> {
        let uuid = self.uuid_c()?;
        let key = ffi::cstring("state key", key)?;
        let value = unsafe { ffi::take_string(sys::actionUIGetElementStateString(uuid.as_ptr(), view_id, key.as_ptr())) };
        match value {
            Some(value) => Ok(Some(value)),
            None => ffi::none_or_error(),
        }
    }

    pub fn set_state<T: Serialize + ?Sized>(&self, view_id: i64, key: &str, value: &T) -> Result<()> {
        let uuid = self.uuid_c()?;
        let key = ffi::cstring("state key", key)?;
        let json = ffi::cstring("state JSON", &serde_json::to_string(value)?)?;
        let accepted = unsafe { sys::actionUISetElementStateJSON(uuid.as_ptr(), view_id, key.as_ptr(), json.as_ptr()) };
        if accepted { Ok(()) } else { Err(ffi::failure("ActionUI did not accept the state value")) }
    }

    pub fn set_state_from_string(&self, view_id: i64, key: &str, value: &str) -> Result<()> {
        let uuid = self.uuid_c()?;
        let key = ffi::cstring("state key", key)?;
        let value = ffi::cstring("state value", value)?;
        let accepted = unsafe { sys::actionUISetElementStateFromString(uuid.as_ptr(), view_id, key.as_ptr(), value.as_ptr()) };
        if accepted { Ok(()) } else { Err(ffi::failure("ActionUI did not accept the state value")) }
    }

    // MARK: - Element list

    /// The elements of the window that have an ID of their own in the JSON, as a map from
    /// the ID to the element type ("TextField", "Button"). Empty for an unknown window.
    pub fn element_info(&self) -> Result<BTreeMap<i64, String>> {
        let uuid = self.uuid_c()?;
        let json = unsafe { ffi::take_string(sys::actionUIGetElementInfoJSON(uuid.as_ptr())) };
        let Some(json) = json else {
            return Ok(BTreeMap::new());
        };
        // JSON object keys are strings; the IDs come back as "2", "3".
        let by_text: BTreeMap<String, String> = serde_json::from_str(&json)?;
        Ok(by_text.into_iter().filter_map(|(id, element_type)| Some((id.parse().ok()?, element_type))).collect())
    }
}

// Changing the structure, and what is presented over the window.
impl Window {
    // MARK: - Inserting and removing elements

    /// Adds an element to a container while the window is open and returns its view ID:
    /// the "id" in `element`, or a negative number ActionUI assigns when there is none.
    ///
    /// `element` is anything that serializes to one element object, such as
    /// `serde_json::json!({ "type": "Text", "id": 50, "properties": { "text": "New" } })`.
    /// `container` names the container property ("children") when the parent has more
    /// than one; `None` picks the only one.
    pub fn insert_element<T: Serialize + ?Sized>(&self, parent_id: i64, element: &T, container: Option<&str>, position: InsertPosition) -> Result<i64> {
        let uuid = self.uuid_c()?;
        let json = ffi::cstring("element JSON", &serde_json::to_string(element)?)?;
        let container = ffi::optional_cstring("container name", container)?;
        let (position, position_param) = position.raw();
        let view_id = unsafe {
            sys::actionUIInsertElement(uuid.as_ptr(), parent_id, json.as_ptr(), ffi::optional_ptr(&container), position, position_param)
        };
        // -1 reports a failure, but it is also a valid ID: ActionUI numbers elements that
        // have no "id" of their own from -1 down. A failure always records an error.
        if view_id == -1 {
            if let Some(message) = ffi::last_error() {
                return Err(Error::ActionUI(message));
            }
        }
        Ok(view_id)
    }

    /// Adds a row of cells to a Grid and returns the view IDs of the cells.
    ///
    /// `cells` is anything that serializes to a list of element objects. A row has no
    /// identity of its own, so the position is [`InsertPosition::Append`],
    /// [`InsertPosition::Prepend`] or [`InsertPosition::At`].
    pub fn insert_row<T: Serialize + ?Sized>(&self, parent_id: i64, cells: &T, container: Option<&str>, position: InsertPosition) -> Result<Vec<i64>> {
        let uuid = self.uuid_c()?;
        let json = ffi::cstring("cells JSON", &serde_json::to_string(cells)?)?;
        let container = ffi::optional_cstring("container name", container)?;
        let (position, position_param) = position.raw();
        let ids = unsafe {
            ffi::take_string(sys::actionUIInsertRow(uuid.as_ptr(), parent_id, json.as_ptr(), ffi::optional_ptr(&container), position, position_param))
        };
        match ids {
            Some(ids) => Ok(serde_json::from_str(&ids)?),
            None => Err(ffi::failure("ActionUI could not insert the row")),
        }
    }

    /// Removes an element and everything inside it. The window's root element cannot be
    /// removed.
    pub fn remove_element(&self, view_id: i64) -> Result<()> {
        let uuid = self.uuid_c()?;
        let removed = unsafe { sys::actionUIRemoveElement(uuid.as_ptr(), view_id) };
        if removed { Ok(()) } else { Err(ffi::failure("ActionUI could not remove the element")) }
    }

    // MARK: - Modal content, alerts and toasts

    /// Presents ActionUI JSON as a sheet over this window. `on_dismiss_action_id` names an
    /// action fired when the sheet goes away, however that happens.
    pub fn present_modal(&self, json: &str, style: ModalStyle, on_dismiss_action_id: Option<&str>) -> Result<()> {
        let uuid = self.uuid_c()?;
        let json = ffi::cstring("modal JSON", json)?;
        let on_dismiss = ffi::optional_cstring("dismiss action ID", on_dismiss_action_id)?;
        let presented = unsafe {
            sys::actionUIPresentModal(uuid.as_ptr(), json.as_ptr(), c"json".as_ptr(), style.raw(), ffi::optional_ptr(&on_dismiss))
        };
        if presented { Ok(()) } else { Err(ffi::failure("ActionUI could not present the modal")) }
    }

    pub fn dismiss_modal(&self) -> Result<()> {
        let uuid = self.uuid_c()?;
        unsafe { sys::actionUIDismissModal(uuid.as_ptr()) };
        Ok(())
    }

    /// Presents an alert attached to this window and returns at once; the answer arrives
    /// as the action of the chosen button. Without buttons the alert has "OK".
    pub fn present_alert(&self, title: &str, message: Option<&str>, buttons: &[DialogButton]) -> Result<()> {
        let uuid = self.uuid_c()?;
        let title = ffi::cstring("alert title", title)?;
        let message = ffi::optional_cstring("alert message", message)?;
        let buttons = if buttons.is_empty() { None } else { Some(ffi::cstring("buttons JSON", &serde_json::to_string(buttons)?)?) };
        let presented = unsafe {
            sys::actionUIPresentAlert(uuid.as_ptr(), title.as_ptr(), ffi::optional_ptr(&message), ffi::optional_ptr(&buttons))
        };
        if presented { Ok(()) } else { Err(ffi::failure("ActionUI could not present the alert")) }
    }

    /// Presents a list of choices attached to this window and returns at once; the answer
    /// arrives as the action of the chosen button.
    pub fn present_confirmation_dialog(&self, title: &str, message: Option<&str>, buttons: &[DialogButton]) -> Result<()> {
        let uuid = self.uuid_c()?;
        let title = ffi::cstring("dialog title", title)?;
        let message = ffi::optional_cstring("dialog message", message)?;
        let buttons = ffi::cstring("buttons JSON", &serde_json::to_string(buttons)?)?;
        let presented = unsafe {
            sys::actionUIPresentConfirmationDialog(uuid.as_ptr(), title.as_ptr(), ffi::optional_ptr(&message), buttons.as_ptr())
        };
        if presented { Ok(()) } else { Err(ffi::failure("ActionUI could not present the dialog")) }
    }

    /// Dismisses the alert or confirmation dialog without any button being chosen.
    pub fn dismiss_dialog(&self) -> Result<()> {
        let uuid = self.uuid_c()?;
        unsafe { sys::actionUIDismissDialog(uuid.as_ptr()) };
        Ok(())
    }

    /// Shows a short message over the window's content that goes away by itself after
    /// `duration`. A toast shown while another is visible waits for its turn. `action` is
    /// an optional inline button: its title and the action it fires.
    pub fn present_toast(&self, message: &str, duration: Duration, action: Option<(&str, &str)>) -> Result<()> {
        let uuid = self.uuid_c()?;
        let message = ffi::cstring("toast message", message)?;
        let action_title = ffi::optional_cstring("toast action title", action.map(|(title, _)| title))?;
        let action_id = ffi::optional_cstring("toast action ID", action.map(|(_, action_id)| action_id))?;
        let presented = unsafe {
            sys::actionUIPresentToast(uuid.as_ptr(), message.as_ptr(), duration.as_secs_f64(), ffi::optional_ptr(&action_title), ffi::optional_ptr(&action_id))
        };
        if presented { Ok(()) } else { Err(ffi::failure("ActionUI could not present the toast")) }
    }

    pub fn dismiss_toast(&self) -> Result<()> {
        let uuid = self.uuid_c()?;
        unsafe { sys::actionUIDismissToast(uuid.as_ptr()) };
        Ok(())
    }
}
