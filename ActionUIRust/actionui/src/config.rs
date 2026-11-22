//! ActionUI's configuration, for every window: limits, trusted servers, the app's
//! resource folder and settings for add-ons, as JSON.
//!
//! Set it before the first window loads its ActionUI JSON; it is fixed after that. Only
//! the keys given change, the rest keep their values:
//!
//! ```no_run
//! actionui::configure(&serde_json::json!({
//!     "limits": {"maximumJSONSize": 32 * 1024 * 1024,        // bytes (16 MB by default)
//!                "loadBudget": {"loads": 256, "seconds": 60},  // LoadableView loads per window
//!                "maximumNestingDepth": 16},                   // LoadableViews inside LoadableViews
//!     "trust": {"trustedOrigins": ["https://ui.example.com"]},  // servers whose JSON is trusted
//!     "resourceFolder": "/path/to/resources",                  // App::set_resource_folder sets this
//!     "addOns": {"SomeAddOn": {}},                              // a section per add-on
//! }))?;
//! # Ok::<(), actionui::Error>(())
//! ```
//!
//! ActionUI JSON from a trusted origin (https, exact scheme, host and port) is trusted as
//! the app's own, but only where the content around it is trusted, and only by the
//! address it finally came from: a redirect from the trusted server to another one gives
//! less-trusted content.

use actionui_sys as sys;

use crate::{Error, Result, ffi};

/// Changes the keys `settings` names in ActionUI's configuration, from any thread. An
/// error, with nothing changed, for an unknown key, a wrong value, an origin that is not
/// https, or a configuration already fixed by a window's load.
pub fn configure(settings: &serde_json::Value) -> Result<()> {
    if !settings.is_object() {
        return Err(Error::ActionUI("the configuration must be an object".to_string()));
    }
    let json = ffi::cstring("configuration", &settings.to_string())?;
    if unsafe { sys::actionUISetConfigurationJSON(json.as_ptr()) } {
        Ok(())
    } else {
        Err(ffi::failure("the configuration was not changed"))
    }
}

/// The configuration in effect, with every key (see [`configure`]).
pub fn configuration() -> Result<serde_json::Value> {
    let json = unsafe { ffi::take_string(sys::actionUIGetConfigurationJSON()) }
        .ok_or_else(|| Error::ActionUI("ActionUI returned no configuration".to_string()))?;
    Ok(serde_json::from_str(&json)?)
}
