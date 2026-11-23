//! Where content came from, and the host's trust policy.
//!
//! A document the host passes in, or one in the app's resources, is trusted; one a
//! LoadableView loads from a server or from a file elsewhere is less trusted, as is
//! anything inside it. ActionUI's own policy refuses less-trusted content a few things
//! (opening other apps' links, reading the user's files, titling the window, covering it
//! with its own sheets). A host changes that with [`set_trust_policy`], and an action
//! handler asks where an element came from with [`crate::Window::element_origin`].

use std::ffi::{CStr, c_char};
use std::sync::{Arc, RwLock};

use actionui_sys as sys;
use serde::Deserialize;

/// How far content is trusted.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Trust {
    LessTrusted,
    Trusted,
}

/// Where content was loaded from.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(tag = "source", rename_all = "camelCase")]
pub enum Source {
    /// JSON the host passed in itself.
    Host,
    /// A file in the app's resources, by its resolved path.
    Resource { path: String },
    /// A local file anywhere else, by its resolved path.
    File { path: String },
    /// An http or https address.
    Remote { url: String },
    /// A source this version of the crate does not know.
    #[serde(other)]
    Unknown,
}

/// The origin of an element's content.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct Origin {
    #[serde(flatten)]
    pub source: Source,
    pub trust: Trust,
    /// The LoadableView (its element ID) the content was loaded into; None for a window's root.
    #[serde(rename = "parentID", default)]
    pub parent_id: Option<i64>,
}

/// Something content asks to do, which the policy allows or refuses.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(tag = "capability")]
pub enum Capability {
    /// A LoadableView loading this source.
    #[serde(rename = "load")]
    Load { source: Source },
    /// A Link, or a link in text, opening this address.
    #[serde(rename = "openLink")]
    OpenLink { url: String },
    /// A WebView showing this address; None for inline html.
    #[serde(rename = "webView")]
    WebView { url: Option<String> },
    /// Inline html in a WebView given this base address.
    #[serde(rename = "webViewBaseURL")]
    WebViewBaseUrl { url: String },
    /// A WebView running the user scripts its content gives.
    #[serde(rename = "webViewUserScripts")]
    WebViewUserScripts,
    /// A WebView keeping its data in the app's persistent store (refused: a private store).
    #[serde(rename = "webViewPersistentData")]
    WebViewPersistentData,
    /// A WebView user script read from this file.
    #[serde(rename = "webViewScriptFile")]
    WebViewScriptFile { path: String },
    /// An image, canvas image, video or shared file read from this local file.
    #[serde(rename = "readLocalFile")]
    ReadLocalFile { path: String },
    /// A VideoPlayer playing this address that is not a local file.
    #[serde(rename = "playMedia")]
    PlayMedia { url: String },
    /// Setting the window's (or a screen's) title.
    #[serde(rename = "windowTitle")]
    WindowTitle,
    /// Presenting a sheet, full-screen cover or popover of its own over the window.
    #[serde(rename = "presentModal")]
    PresentModal,
    /// Adding menu commands.
    #[serde(rename = "menuCommands")]
    MenuCommands,
    /// Firing this action.
    #[serde(rename = "action")]
    Action {
        #[serde(rename = "actionID")]
        action_id: String,
    },
    /// A HostSurface element binding to the host's surface of this name.
    #[serde(rename = "hostSurface")]
    HostSurface {
        #[serde(rename = "surfaceName")]
        surface_name: String,
    },
    /// A capability this version of the crate does not know.
    #[serde(other)]
    Unknown,
}

/// The host's trust policy. Each method receives ActionUI's own decision, `by_default`, and
/// returns the one to use; a method left out keeps ActionUI's. The methods run on the main
/// thread, often (as elements draw), and should return quickly. One that panics counts as
/// less trusted, or as a refusal.
pub trait TrustPolicy: Send + Sync + 'static {
    /// The trust of content a LoadableView loads from `source` inside content of origin
    /// `parent` (None only for a window's root; a LoadableView whose surroundings cannot be
    /// told gets a less-trusted parent).
    fn trust(&self, source: &Source, parent: Option<&Origin>, by_default: Trust) -> Trust {
        let _ = (source, parent);
        by_default
    }

    /// Whether content of `origin` may do `capability`.
    fn allows(&self, capability: &Capability, origin: &Origin, by_default: bool) -> bool {
        let _ = (capability, origin);
        by_default
    }
}

type Policy = Arc<dyn TrustPolicy>;

static POLICY: RwLock<Option<Policy>> = RwLock::new(None);

/// The policy, cloned out so it is not called with the lock held: a policy that sets another
/// one would otherwise deadlock.
fn current() -> Option<Policy> {
    POLICY.read().ok().and_then(|slot| slot.clone())
}

/// The JSON text at `pointer` parsed as `T`; None for a null pointer or text that does not parse.
unsafe fn parse<T: for<'a> Deserialize<'a>>(pointer: *const c_char) -> Option<T> {
    if pointer.is_null() {
        return None;
    }
    let text = unsafe { CStr::from_ptr(pointer) }.to_str().ok()?;
    serde_json::from_str(text).ok()
}

unsafe extern "C" fn trust_trampoline(
    source: *const c_char,
    parent: *const c_char,
    by_default: sys::ActionUITrust,
) -> sys::ActionUITrust {
    let Some(policy) = current() else {
        return by_default;
    };
    // Fails closed: a source or parent that does not parse, or a panic, is less trusted.
    let Some(source) = (unsafe { parse::<Source>(source) }) else {
        return sys::ACTIONUI_TRUST_LESS_TRUSTED;
    };
    let parent = if parent.is_null() {
        None
    } else {
        match unsafe { parse::<Origin>(parent) } {
            Some(parent) => Some(parent),
            None => return sys::ACTIONUI_TRUST_LESS_TRUSTED,
        }
    };
    let default = if by_default == sys::ACTIONUI_TRUST_TRUSTED { Trust::Trusted } else { Trust::LessTrusted };
    let decided = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| policy.trust(&source, parent.as_ref(), default)));
    match decided {
        Ok(Trust::Trusted) => sys::ACTIONUI_TRUST_TRUSTED,
        _ => sys::ACTIONUI_TRUST_LESS_TRUSTED,
    }
}

unsafe extern "C" fn allows_trampoline(capability: *const c_char, origin: *const c_char, by_default: bool) -> bool {
    let Some(policy) = current() else {
        return by_default;
    };
    // Fails closed: a capability or origin that does not parse, or a panic, is refused.
    let (Some(capability), Some(origin)) = (unsafe { parse::<Capability>(capability) }, unsafe { parse::<Origin>(origin) }) else {
        return false;
    };
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| policy.allows(&capability, &origin, by_default))).unwrap_or(false)
}

/// Sets the host's trust policy, for all windows, from any thread; set it before loading
/// content.
pub fn set_trust_policy(policy: impl TrustPolicy) {
    // The old policy is dropped after the lock is released: its destructors may call back in.
    let old = POLICY.write().ok().and_then(|mut slot| slot.replace(Arc::new(policy)));
    drop(old);
    unsafe { sys::actionUISetTrustPolicy(Some(trust_trampoline), Some(allows_trampoline)) };
}

/// Restores ActionUI's own trust policy.
pub fn clear_trust_policy() {
    unsafe { sys::actionUISetTrustPolicy(None, None) };
    let old = POLICY.write().ok().and_then(|mut slot| slot.take());
    drop(old);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn origins_parse_from_the_c_adapters_json() {
        let remote: Origin = serde_json::from_str(r#"{"source":"remote","url":"https://example.com/v.json","trust":"lessTrusted","parentID":3}"#).unwrap();
        assert_eq!(remote.source, Source::Remote { url: "https://example.com/v.json".into() });
        assert_eq!(remote.trust, Trust::LessTrusted);
        assert_eq!(remote.parent_id, Some(3));
        let host: Origin = serde_json::from_str(r#"{"source":"host","trust":"trusted"}"#).unwrap();
        assert_eq!((host.source, host.trust, host.parent_id), (Source::Host, Trust::Trusted, None));
        let newer: Origin = serde_json::from_str(r#"{"source":"somethingNew","trust":"trusted"}"#).unwrap();
        assert_eq!(newer.source, Source::Unknown);
    }

    #[test]
    fn capabilities_parse_from_the_c_adapters_json() {
        let cases: [(&str, Capability); 6] = [
            (r#"{"capability":"readLocalFile","path":"/tmp/a.png"}"#, Capability::ReadLocalFile { path: "/tmp/a.png".into() }),
            (r#"{"capability":"webView","url":null}"#, Capability::WebView { url: None }),
            (r#"{"capability":"webViewBaseURL","url":"https://a.example/"}"#, Capability::WebViewBaseUrl { url: "https://a.example/".into() }),
            (r#"{"capability":"load","source":{"source":"file","path":"/tmp/v.json"}}"#, Capability::Load { source: Source::File { path: "/tmp/v.json".into() } }),
            (r#"{"capability":"action","actionID":"app.save"}"#, Capability::Action { action_id: "app.save".into() }),
            (r#"{"capability":"somethingNew"}"#, Capability::Unknown),
        ];
        for (json, expected) in cases {
            assert_eq!(serde_json::from_str::<Capability>(json).unwrap(), expected, "{json}");
        }
        assert_eq!(serde_json::from_str::<Capability>(r#"{"capability":"windowTitle"}"#).unwrap(), Capability::WindowTitle);
        assert_eq!(serde_json::from_str::<Capability>(r#"{"capability":"webViewUserScripts"}"#).unwrap(), Capability::WebViewUserScripts);
        assert_eq!(serde_json::from_str::<Capability>(r#"{"capability":"webViewPersistentData"}"#).unwrap(),
                   Capability::WebViewPersistentData);
        assert_eq!(serde_json::from_str::<Capability>(r#"{"capability":"hostSurface","surfaceName":"viewport"}"#).unwrap(),
                   Capability::HostSurface { surface_name: "viewport".into() });
        assert_eq!(serde_json::from_str::<Capability>(r#"{"capability":"playMedia","url":"https://example.com/v.mp4"}"#).unwrap(),
                   Capability::PlayMedia { url: "https://example.com/v.mp4".into() });
    }

    struct Panics;

    impl TrustPolicy for Panics {
        fn trust(&self, _: &Source, _: Option<&Origin>, _: Trust) -> Trust {
            panic!("expected: the policy panics")
        }

        fn allows(&self, _: &Capability, _: &Origin, _: bool) -> bool {
            panic!("expected: the policy panics")
        }
    }

    #[test]
    fn trampolines_fail_closed() {
        // Stored directly: actionUISetTrustPolicy waits for a main thread the test harness does not run.
        *POLICY.write().unwrap() = Some(Arc::new(Panics));
        let source = c"{\"source\":\"resource\",\"path\":\"/a/v.json\"}";
        let origin = c"{\"source\":\"host\",\"trust\":\"trusted\"}";
        let capability = c"{\"capability\":\"windowTitle\"}";
        let not_json = c"not json";
        unsafe {
            // A panic is less trusted, or a refusal, whatever the default.
            assert_eq!(trust_trampoline(source.as_ptr(), origin.as_ptr(), sys::ACTIONUI_TRUST_TRUSTED), sys::ACTIONUI_TRUST_LESS_TRUSTED);
            assert!(!allows_trampoline(capability.as_ptr(), origin.as_ptr(), true));
            // So is JSON that does not parse.
            assert_eq!(trust_trampoline(not_json.as_ptr(), std::ptr::null(), sys::ACTIONUI_TRUST_TRUSTED), sys::ACTIONUI_TRUST_LESS_TRUSTED);
            assert_eq!(trust_trampoline(source.as_ptr(), not_json.as_ptr(), sys::ACTIONUI_TRUST_TRUSTED), sys::ACTIONUI_TRUST_LESS_TRUSTED);
            assert!(!allows_trampoline(not_json.as_ptr(), origin.as_ptr(), true));
        }
        POLICY.write().unwrap().take();
    }
}
