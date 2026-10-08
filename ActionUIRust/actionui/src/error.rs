use std::fmt;

/// Everything that can go wrong in this crate.
#[derive(Debug)]
pub enum Error {
    /// The call was made from a thread other than the main thread. Hand the work to the
    /// main thread with [`crate::main_thread::dispatch`].
    NotMainThread,
    /// [`crate::App::new`] was called a second time. Use [`crate::App::get`].
    AppAlreadyCreated,
    /// A string passed to ActionUI contains a zero byte. The field names which string.
    InteriorNul(&'static str),
    /// ActionUI refused the call or could not complete it. The text is ActionUI's own.
    ActionUI(String),
    /// A value could not be converted to or from JSON.
    Json(serde_json::Error),
    /// A file could not be read or written.
    Io(std::io::Error),
}

pub type Result<T> = std::result::Result<T, Error>;

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::NotMainThread => write!(f, "ActionUI was called from a thread other than the main thread"),
            Error::AppAlreadyCreated => write!(f, "the ActionUI application object already exists"),
            Error::InteriorNul(what) => write!(f, "the {what} contains a zero byte"),
            Error::ActionUI(message) => write!(f, "{message}"),
            Error::Json(error) => write!(f, "JSON conversion failed: {error}"),
            Error::Io(error) => write!(f, "{error}"),
        }
    }
}

impl std::error::Error for Error {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Error::Json(error) => Some(error),
            Error::Io(error) => Some(error),
            _ => None,
        }
    }
}

impl From<serde_json::Error> for Error {
    fn from(error: serde_json::Error) -> Self {
        Error::Json(error)
    }
}

impl From<std::io::Error> for Error {
    fn from(error: std::io::Error) -> Self {
        Error::Io(error)
    }
}
