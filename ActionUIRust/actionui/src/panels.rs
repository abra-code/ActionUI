//! Application-modal panels: an alert, and the file open and save panels.
//!
//! Each `run` blocks until the user answers, with the event loop still running underneath
//! it, so other handlers can run in the meantime. They need the [`App`] token, which
//! exists only on the main thread.

use std::path::PathBuf;

use actionui_sys as sys;
use serde::Serialize;

use crate::app::App;
use crate::error::Result;
use crate::ffi;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum AlertStyle {
    #[default]
    Informational,
    Warning,
    Critical,
}

/// An alert in its own window, not attached to any window of the application. For an
/// alert attached to a window, see [`crate::Window::present_alert`].
///
/// ```no_run
/// # fn example(app: actionui::App) -> actionui::Result<()> {
/// use actionui::panels::{Alert, AlertStyle};
///
/// let answer = Alert::new("Discard the draft?")
///     .message("This cannot be undone.")
///     .style(AlertStyle::Warning)
///     .buttons(["Discard", "Cancel"])
///     .run(app)?;
/// if answer.as_deref() == Some("Discard") {
///     // ...
/// }
/// # Ok(()) }
/// ```
#[derive(Debug, Clone, Default, Serialize)]
pub struct Alert {
    title: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    message: Option<String>,
    style: AlertStyle,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    buttons: Vec<String>,
}

impl Alert {
    pub fn new(title: impl Into<String>) -> Alert {
        Alert { title: title.into(), ..Alert::default() }
    }

    /// The smaller text under the title.
    pub fn message(mut self, message: impl Into<String>) -> Alert {
        self.message = Some(message.into());
        self
    }

    pub fn style(mut self, style: AlertStyle) -> Alert {
        self.style = style;
        self
    }

    /// Button titles. The first is the default button. Without any, the alert has "OK".
    pub fn buttons<S: Into<String>>(mut self, titles: impl IntoIterator<Item = S>) -> Alert {
        self.buttons = titles.into_iter().map(Into::into).collect();
        self
    }

    /// Shows the alert and returns the title of the button the user chose.
    pub fn run(self, _app: App) -> Result<Option<String>> {
        let config = ffi::cstring("alert description", &serde_json::to_string(&self)?)?;
        Ok(unsafe { ffi::take_string(sys::actionUIAppRunAlert(config.as_ptr())) })
    }
}

/// What the open and save panels have in common.
#[derive(Debug, Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
struct PanelOptions {
    #[serde(skip_serializing_if = "Option::is_none")]
    title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    prompt: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    message: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    identifier: Option<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    allowed_content_types: Vec<String>,
    #[serde(rename = "directoryURL", skip_serializing_if = "Option::is_none")]
    directory: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    shows_hidden_files: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    treats_file_packages_as_directories: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    can_create_directories: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    allows_other_file_types: Option<bool>,
}

// The options shared by both panels, written once.
macro_rules! common_panel_options {
    () => {
        /// The panel's window title.
        pub fn title(mut self, title: impl Into<String>) -> Self {
            self.common.title = Some(title.into());
            self
        }

        /// The label of the confirming button.
        pub fn prompt(mut self, prompt: impl Into<String>) -> Self {
            self.common.prompt = Some(prompt.into());
            self
        }

        /// A line of text shown at the top of the panel.
        pub fn message(mut self, message: impl Into<String>) -> Self {
            self.common.message = Some(message.into());
            self
        }

        /// A name under which the system remembers this panel's last folder and size.
        pub fn identifier(mut self, identifier: impl Into<String>) -> Self {
            self.common.identifier = Some(identifier.into());
            self
        }

        /// The file types that can be chosen: file extensions ("json") or uniform type
        /// identifiers ("public.image").
        pub fn allowed_types<S: Into<String>>(mut self, types: impl IntoIterator<Item = S>) -> Self {
            self.common.allowed_content_types = types.into_iter().map(Into::into).collect();
            self
        }

        /// The folder the panel opens in.
        pub fn directory(mut self, directory: impl AsRef<std::path::Path>) -> Self {
            self.common.directory = Some(directory.as_ref().to_string_lossy().into_owned());
            self
        }

        pub fn shows_hidden_files(mut self, shows: bool) -> Self {
            self.common.shows_hidden_files = Some(shows);
            self
        }

        /// Lets the user look inside packages such as `.app` bundles.
        pub fn treats_file_packages_as_directories(mut self, treats: bool) -> Self {
            self.common.treats_file_packages_as_directories = Some(treats);
            self
        }

        pub fn can_create_directories(mut self, can: bool) -> Self {
            self.common.can_create_directories = Some(can);
            self
        }

        pub fn allows_other_file_types(mut self, allows: bool) -> Self {
            self.common.allows_other_file_types = Some(allows);
            self
        }
    };
}

/// The system panel for choosing existing files or folders.
///
/// ```no_run
/// # fn example(app: actionui::App) -> actionui::Result<()> {
/// use actionui::panels::OpenPanel;
///
/// if let Some(paths) = OpenPanel::new().allowed_types(["json"]).allows_multiple_selection(true).run(app)? {
///     for path in paths {
///         println!("{}", path.display());
///     }
/// }
/// # Ok(()) }
/// ```
#[derive(Debug, Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OpenPanel {
    #[serde(flatten)]
    common: PanelOptions,
    #[serde(skip_serializing_if = "Option::is_none")]
    allows_multiple_selection: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    can_choose_directories: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    can_choose_files: Option<bool>,
}

impl OpenPanel {
    /// A panel that lets the user choose one file.
    pub fn new() -> OpenPanel {
        OpenPanel::default()
    }

    common_panel_options!();

    pub fn allows_multiple_selection(mut self, allows: bool) -> OpenPanel {
        self.allows_multiple_selection = Some(allows);
        self
    }

    pub fn can_choose_directories(mut self, can: bool) -> OpenPanel {
        self.can_choose_directories = Some(can);
        self
    }

    pub fn can_choose_files(mut self, can: bool) -> OpenPanel {
        self.can_choose_files = Some(can);
        self
    }

    /// Shows the panel. `None` when the user canceled.
    pub fn run(self, _app: App) -> Result<Option<Vec<PathBuf>>> {
        let config = ffi::cstring("open panel description", &serde_json::to_string(&self)?)?;
        let chosen = unsafe { ffi::take_string(sys::actionUIAppRunOpenPanel(config.as_ptr())) };
        match chosen {
            Some(json) => {
                let paths: Vec<String> = serde_json::from_str(&json)?;
                Ok(Some(paths.into_iter().map(PathBuf::from).collect()))
            }
            None => Ok(None),
        }
    }
}

/// The system panel for choosing where to save a file.
#[derive(Debug, Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SavePanel {
    #[serde(flatten)]
    common: PanelOptions,
    #[serde(rename = "nameFieldStringValue", skip_serializing_if = "Option::is_none")]
    file_name: Option<String>,
}

impl SavePanel {
    pub fn new() -> SavePanel {
        SavePanel::default()
    }

    common_panel_options!();

    /// The file name the panel proposes.
    pub fn file_name(mut self, file_name: impl Into<String>) -> SavePanel {
        self.file_name = Some(file_name.into());
        self
    }

    /// Shows the panel. `None` when the user canceled.
    pub fn run(self, _app: App) -> Result<Option<PathBuf>> {
        let config = ffi::cstring("save panel description", &serde_json::to_string(&self)?)?;
        let chosen = unsafe { ffi::take_string(sys::actionUIAppRunSavePanel(config.as_ptr())) };
        Ok(chosen.map(PathBuf::from))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_alert_serializes_to_the_keys_actionui_reads() {
        let alert = Alert::new("Title").message("Text").style(AlertStyle::Critical).buttons(["Yes", "No"]);
        assert_eq!(
            serde_json::to_string(&alert).unwrap(),
            r#"{"title":"Title","message":"Text","style":"critical","buttons":["Yes","No"]}"#
        );
        assert_eq!(serde_json::to_string(&Alert::new("T")).unwrap(), r#"{"title":"T","style":"informational"}"#);
    }

    #[test]
    fn an_open_panel_serializes_only_what_was_set() {
        assert_eq!(serde_json::to_string(&OpenPanel::new()).unwrap(), "{}");
        let panel = OpenPanel::new()
            .title("Pick")
            .allowed_types(["json", "public.image"])
            .directory("/tmp")
            .can_choose_directories(true)
            .allows_multiple_selection(true);
        assert_eq!(
            serde_json::to_string(&panel).unwrap(),
            r#"{"title":"Pick","allowedContentTypes":["json","public.image"],"directoryURL":"/tmp","allowsMultipleSelection":true,"canChooseDirectories":true}"#
        );
    }

    #[test]
    fn a_save_panel_serializes_the_proposed_name() {
        let panel = SavePanel::new().file_name("Untitled.json").can_create_directories(true);
        assert_eq!(
            serde_json::to_string(&panel).unwrap(),
            r#"{"canCreateDirectories":true,"nameFieldStringValue":"Untitled.json"}"#
        );
    }
}
