//! The types that describe dialogs presented inside a window, and where to insert elements.

use serde::Serialize;

use actionui_sys as sys;

/// How a modal is presented over its window.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
pub enum ModalStyle {
    #[default]
    Sheet,
    /// Covers the whole window. On macOS it is shown as a sheet.
    FullScreenCover,
}

impl ModalStyle {
    pub(crate) fn raw(self) -> sys::ActionUIModalStyle {
        match self {
            ModalStyle::Sheet => sys::ACTIONUI_MODAL_STYLE_SHEET,
            ModalStyle::FullScreenCover => sys::ACTIONUI_MODAL_STYLE_FULL_SCREEN_COVER,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum ButtonRole {
    #[default]
    Default,
    Cancel,
    /// Shown in red.
    Destructive,
}

impl ButtonRole {
    fn is_default(&self) -> bool {
        *self == ButtonRole::Default
    }
}

/// One button of an alert or a confirmation dialog.
///
/// ```
/// use actionui::{ButtonRole, DialogButton};
///
/// let buttons = [
///     DialogButton::new("Delete").role(ButtonRole::Destructive).action("item.delete"),
///     DialogButton::new("Cancel").role(ButtonRole::Cancel),
/// ];
/// ```
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct DialogButton {
    title: String,
    #[serde(skip_serializing_if = "ButtonRole::is_default")]
    role: ButtonRole,
    #[serde(rename = "actionID", skip_serializing_if = "Option::is_none")]
    action_id: Option<String>,
}

impl DialogButton {
    /// A button that only dismisses the dialog.
    pub fn new(title: impl Into<String>) -> DialogButton {
        DialogButton { title: title.into(), role: ButtonRole::Default, action_id: None }
    }

    pub fn role(mut self, role: ButtonRole) -> DialogButton {
        self.role = role;
        self
    }

    /// The action fired when the button is chosen, received like any other action.
    pub fn action(mut self, action_id: impl Into<String>) -> DialogButton {
        self.action_id = Some(action_id.into());
        self
    }
}

/// Where a new element or row goes in its container.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
pub enum InsertPosition {
    /// After the last existing child.
    #[default]
    Append,
    /// Before the first existing child.
    Prepend,
    /// At this 0-based index.
    At(i64),
    /// Before the sibling with this view ID. Not for rows.
    Before(i64),
    /// After the sibling with this view ID. Not for rows.
    After(i64),
}

impl InsertPosition {
    pub(crate) fn raw(self) -> (sys::ActionUIInsertPosition, i64) {
        match self {
            InsertPosition::Append => (sys::ACTIONUI_INSERT_POSITION_APPEND, 0),
            InsertPosition::Prepend => (sys::ACTIONUI_INSERT_POSITION_PREPEND, 0),
            InsertPosition::At(index) => (sys::ACTIONUI_INSERT_POSITION_AT, index),
            InsertPosition::Before(sibling) => (sys::ACTIONUI_INSERT_POSITION_BEFORE, sibling),
            InsertPosition::After(sibling) => (sys::ACTIONUI_INSERT_POSITION_AFTER, sibling),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn buttons_serialize_to_the_format_actionui_reads() {
        let buttons = [
            DialogButton::new("Delete").role(ButtonRole::Destructive).action("item.delete"),
            DialogButton::new("Cancel").role(ButtonRole::Cancel),
            DialogButton::new("OK"),
        ];
        assert_eq!(
            serde_json::to_string(&buttons).unwrap(),
            r#"[{"title":"Delete","role":"destructive","actionID":"item.delete"},{"title":"Cancel","role":"cancel"},{"title":"OK"}]"#
        );
    }

    #[test]
    fn insert_positions_carry_their_parameter() {
        assert_eq!(InsertPosition::Append.raw(), (sys::ACTIONUI_INSERT_POSITION_APPEND, 0));
        assert_eq!(InsertPosition::At(3).raw(), (sys::ACTIONUI_INSERT_POSITION_AT, 3));
        assert_eq!(InsertPosition::After(12).raw(), (sys::ACTIONUI_INSERT_POSITION_AFTER, 12));
    }
}
