//! The application: its event loop, its windows and the handlers for what happens in them.

use std::cell::RefCell;
use std::collections::HashMap;
use std::ffi::{CStr, c_char};
use std::fs;
use std::marker::PhantomData;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::sync::atomic::{AtomicBool, Ordering};

use actionui_sys as sys;
use serde::de::DeserializeOwned;

use crate::error::{Error, Result};
use crate::ffi;
use crate::window::Window;

/// What an action handler is told about the action.
#[derive(Debug, Clone)]
pub struct ActionContext {
    /// The `actionID` from the JSON.
    pub action_id: String,
    /// The window the action came from. A menu bar action names the frontmost window;
    /// its UUID is empty when there is none.
    pub window: Window,
    /// The `id` of the element, or 0 when the action has none (a menu item).
    pub view_id: i64,
    /// The part of the element, for elements that have parts; otherwise 0.
    pub view_part_id: i64,
    /// Extra data some elements send with the action.
    pub context: Option<serde_json::Value>,
}

impl ActionContext {
    /// The application. Handlers run on the main thread, after [`App::new`], so it exists.
    ///
    /// # Panics
    ///
    /// When called on another thread: this value can be cloned and sent to a worker,
    /// and the application token must not exist there.
    pub fn app(&self) -> App {
        assert!(ffi::is_main_thread(), "ActionContext::app was called from a thread other than the main thread");
        App::token()
    }

    /// The extra data, read into a type of your own. `Ok(None)` when the action has none.
    pub fn context_as<T: DeserializeOwned>(&self) -> Result<Option<T>> {
        match &self.context {
            Some(value) => Ok(Some(T::deserialize(value)?)),
            None => Ok(None),
        }
    }
}

type ActionHandler = Rc<dyn Fn(&ActionContext)>;
type EventHandler = Rc<dyn Fn()>;
type WindowHandler = Rc<dyn Fn(&Window)>;

#[derive(Default)]
struct Handlers {
    actions: HashMap<String, ActionHandler>,
    any_action: Option<ActionHandler>,
    will_finish_launching: Option<EventHandler>,
    did_finish_launching: Option<EventHandler>,
    will_become_active: Option<EventHandler>,
    did_become_active: Option<EventHandler>,
    will_resign_active: Option<EventHandler>,
    did_resign_active: Option<EventHandler>,
    will_terminate: Option<EventHandler>,
    should_terminate: Option<Rc<dyn Fn() -> bool>>,
    window_will_close: Option<WindowHandler>,
    window_will_present: Option<WindowHandler>,
    /// Holds the JSON of windows presented from a string; removed at termination.
    scratch_dir: Option<PathBuf>,
}

// Handlers are registered and called on the main thread only, so they live in that
// thread's storage and need not be Send. A handler is cloned out of the table before it
// is called: it may register or remove handlers itself, and may be entered again while
// it is running (a handler that shows a modal alert keeps the event loop going).
//
// A handler being replaced or removed is moved out of the table and dropped after the
// borrow has ended (`replace`, `insert` and `remove` return it): dropping it runs the
// destructors of what it captured, and those may come back here.
thread_local! {
    static HANDLERS: RefCell<Handlers> = RefCell::new(Handlers::default());
}

static APP_CREATED: AtomicBool = AtomicBool::new(false);

fn event_handler(select: impl FnOnce(&Handlers) -> Option<EventHandler>) -> Option<EventHandler> {
    HANDLERS.with(|handlers| select(&handlers.borrow()))
}

fn run_event(what: &str, select: impl FnOnce(&Handlers) -> Option<EventHandler>) {
    if let Some(handler) = event_handler(select) {
        ffi::guard(what, (), move || handler());
    }
}

unsafe extern "C" fn action_trampoline(
    action_id: *const c_char,
    window_uuid: *const c_char,
    view_id: i64,
    view_part_id: i64,
    context_json: *const c_char,
) {
    if action_id.is_null() {
        return;
    }
    let action_id = unsafe { CStr::from_ptr(action_id) }.to_string_lossy().into_owned();
    let window_uuid = unsafe { ffi::copy_string(window_uuid) }.unwrap_or_default();
    let context_text = unsafe { ffi::copy_string(context_json) };

    let handler = HANDLERS.with(|handlers| {
        let handlers = handlers.borrow();
        handlers.actions.get(&action_id).cloned().or_else(|| handlers.any_action.clone())
    });
    let Some(handler) = handler else {
        let _ = crate::log::log(
            crate::log::LogLevel::Warning,
            &format!("No Rust handler is registered for action '{action_id}'"),
        );
        return;
    };

    // ActionUI produced this JSON itself; text that still does not parse is passed on as
    // a string instead of being dropped.
    let context = context_text
        .map(|text| serde_json::from_str(&text).unwrap_or(serde_json::Value::String(text)));
    let action = ActionContext {
        action_id,
        window: Window::with_uuid(&window_uuid),
        view_id,
        view_part_id,
        context,
    };
    ffi::guard("action handler", (), move || handler(&action));
}

unsafe extern "C" fn will_finish_launching_trampoline() {
    run_event("will-finish-launching handler", |handlers| handlers.will_finish_launching.clone());
}

unsafe extern "C" fn did_finish_launching_trampoline() {
    run_event("did-finish-launching handler", |handlers| handlers.did_finish_launching.clone());
}

unsafe extern "C" fn will_become_active_trampoline() {
    run_event("will-become-active handler", |handlers| handlers.will_become_active.clone());
}

unsafe extern "C" fn did_become_active_trampoline() {
    run_event("did-become-active handler", |handlers| handlers.did_become_active.clone());
}

unsafe extern "C" fn will_resign_active_trampoline() {
    run_event("will-resign-active handler", |handlers| handlers.will_resign_active.clone());
}

unsafe extern "C" fn did_resign_active_trampoline() {
    run_event("did-resign-active handler", |handlers| handlers.did_resign_active.clone());
}

unsafe extern "C" fn will_terminate_trampoline() {
    // The process ends in exit() right after this, so nothing else gets a chance to
    // remove the scratch files. Done before the user's handler, which may itself exit.
    let scratch_dir = HANDLERS.with(|handlers| handlers.borrow_mut().scratch_dir.take());
    if let Some(scratch_dir) = scratch_dir {
        let _ = fs::remove_dir_all(scratch_dir);
    }
    run_event("will-terminate handler", |handlers| handlers.will_terminate.clone());
}

unsafe extern "C" fn should_terminate_trampoline() -> bool {
    let handler = HANDLERS.with(|handlers| handlers.borrow().should_terminate.clone());
    match handler {
        // A handler that panics has not refused, so termination goes ahead.
        Some(handler) => ffi::guard("should-terminate handler", true, move || handler()),
        None => true,
    }
}

fn run_window_event(what: &str, window_uuid: *const c_char, select: impl FnOnce(&Handlers) -> Option<WindowHandler>) {
    let handler = HANDLERS.with(|handlers| select(&handlers.borrow()));
    let Some(handler) = handler else {
        return;
    };
    let Some(window_uuid) = (unsafe { ffi::copy_string(window_uuid) }) else {
        return;
    };
    let window = Window::with_uuid(&window_uuid);
    ffi::guard(what, (), move || handler(&window));
}

unsafe extern "C" fn window_will_close_trampoline(window_uuid: *const c_char) {
    run_window_event("window-will-close handler", window_uuid, |handlers| handlers.window_will_close.clone());
}

unsafe extern "C" fn window_will_present_trampoline(window_uuid: *const c_char) {
    run_window_event("window-will-present handler", window_uuid, |handlers| handlers.window_will_present.clone());
}

/// Writes a path as a `file://` URL.
fn file_url(path: &Path) -> String {
    use std::os::unix::ffi::OsStrExt;
    let mut url = String::from("file://");
    for &byte in path.as_os_str().as_bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' | b'/' => url.push(byte as char),
            _ => url.push_str(&format!("%{byte:02X}")),
        }
    }
    url
}

/// The application. Created once, on the main thread, with [`App::new`].
///
/// The value is a token that stands for "the application exists and this is the main
/// thread". It is `Copy`, so handlers can capture it, and it cannot leave the main thread.
///
/// ActionUI's application layer creates the windows and the menu bar and runs the event
/// loop; this program only describes them and reacts.
#[derive(Debug, Clone, Copy)]
pub struct App {
    // A raw pointer makes the type neither Send nor Sync.
    _main_thread_only: PhantomData<*const ()>,
}

impl App {
    fn token() -> App {
        App { _main_thread_only: PhantomData }
    }

    /// Creates the application. Fails off the main thread, and when called twice.
    pub fn new() -> Result<App> {
        ffi::require_main_thread()?;
        if APP_CREATED.swap(true, Ordering::SeqCst) {
            return Err(Error::AppAlreadyCreated);
        }
        // One C handler receives every action and finds the Rust closure for it; the C
        // handler type has no room for a closure's captured state.
        unsafe {
            sys::actionUISetDefaultActionHandler(Some(action_trampoline));
            sys::actionUIAppSetWillTerminateHandler(Some(will_terminate_trampoline));
        }
        Ok(App::token())
    }

    /// The application, if [`App::new`] has been called and this is the main thread.
    pub fn get() -> Option<App> {
        (ffi::is_main_thread() && APP_CREATED.load(Ordering::SeqCst)).then(App::token)
    }

    /// Names the application in the menu bar and the Dock. For a program that runs as a
    /// bare executable (`cargo run`). Do not call it in a program packaged as an `.app`
    /// bundle: the bundle's Info.plist already names it, and this call discards the rest
    /// of what that file declares. Call it before [`App::run`].
    pub fn set_name(&self, name: &str) -> Result<()> {
        let name = ffi::cstring("application name", name)?;
        unsafe { sys::actionUIAppSetName(name.as_ptr()) };
        Ok(())
    }

    /// Sets the Dock and About-panel icon from an image file (icns, png and others).
    /// Call it before [`App::run`]. A file that is not an image is ignored.
    pub fn set_icon(&self, path: impl AsRef<Path>) -> Result<()> {
        let path = path.as_ref().to_string_lossy();
        let path = ffi::cstring("icon path", &path)?;
        unsafe { sys::actionUIAppSetIcon(path.as_ptr()) };
        Ok(())
    }

    /// Runs the event loop. It does not return: quitting the application ends the
    /// process from inside the loop, so code after this call, and the destructors of
    /// values still alive in `main`, do not run. (Handlers, and what they captured, are
    /// dropped as the process exits.) Do final work in
    /// [`App::on_will_terminate`].
    pub fn run(self) -> ! {
        unsafe { sys::actionUIAppRun() };
        std::process::exit(0)
    }

    /// Asks the application to quit, as the Quit menu item does, and returns. The
    /// [`App::on_should_terminate`] handler can still refuse.
    pub fn terminate(&self) {
        // Queued instead of called directly: on the main thread ActionUI would run the
        // whole termination, exit() included, inside the caller's handler.
        crate::main_thread::dispatch(|| unsafe { sys::actionUIAppTerminate() });
    }

    // MARK: - Windows

    /// Opens a window showing the ActionUI JSON in a file. Without a title the window is
    /// named after the file.
    pub fn present_window_from_file(&self, path: impl AsRef<Path>, title: Option<&str>) -> Result<Window> {
        // Resolved here so a missing file is an error now, not a blank window later.
        let path = fs::canonicalize(path.as_ref())?;
        self.present_window_from_url(&file_url(&path), title)
    }

    /// Opens a window showing the ActionUI JSON at a `file://`, `http://` or `https://`
    /// URL. Content from the network is loaded after the window appears.
    pub fn present_window_from_url(&self, url: &str, title: Option<&str>) -> Result<Window> {
        // ActionUI only logs a URL it cannot use, and this would return a handle to a
        // window that never opens.
        if url.trim().is_empty() {
            return Err(Error::ActionUI("the window URL is empty".to_string()));
        }
        let window = Window::with_uuid(&ffi::new_uuid());
        let url = ffi::cstring("window URL", url)?;
        let uuid = ffi::cstring("window UUID", window.uuid())?;
        let title = ffi::optional_cstring("window title", title)?;
        unsafe { sys::actionUIAppLoadAndPresentWindow(url.as_ptr(), uuid.as_ptr(), ffi::optional_ptr(&title)) };
        Ok(window)
    }

    /// Opens a window showing ActionUI JSON held in a string, typically one compiled into
    /// the program with `include_str!`.
    ///
    /// ActionUI's application layer loads windows from URLs only, so the text is written
    /// to a file in the temporary directory first. The file is removed at termination.
    pub fn present_window_from_json(&self, json: &str, title: &str) -> Result<Window> {
        let scratch_dir = HANDLERS.with(|handlers| -> Result<PathBuf> {
            let mut handlers = handlers.borrow_mut();
            if let Some(dir) = &handlers.scratch_dir {
                return Ok(dir.clone());
            }
            let dir = std::env::temp_dir().join(format!("actionui-rust-{}", ffi::new_uuid()));
            fs::create_dir_all(&dir)?;
            handlers.scratch_dir = Some(dir.clone());
            Ok(dir)
        })?;
        let path = scratch_dir.join(format!("{}.json", ffi::new_uuid()));
        fs::write(&path, json)?;
        self.present_window_from_file(&path, Some(title))
    }

    // MARK: - Actions

    /// Runs `handler` for every action with this `actionID`: a button press, a menu item,
    /// a changed value, whatever the JSON attaches the ID to. Replaces an earlier handler
    /// for the same ID.
    ///
    /// The handler is `Fn`, not `FnMut`, because it can be entered again while it runs (a
    /// handler that shows a modal alert keeps the event loop going). Keep changing state
    /// in a `Cell` or `RefCell`.
    pub fn on_action(&self, action_id: impl Into<String>, handler: impl Fn(&ActionContext) + 'static) {
        // Converted first: `into` is the caller's code and must not run inside the borrow.
        let action_id = action_id.into();
        HANDLERS.with(|handlers| handlers.borrow_mut().actions.insert(action_id, Rc::new(handler)));
    }

    /// Removes the handler for one `actionID`.
    pub fn remove_action(&self, action_id: &str) {
        HANDLERS.with(|handlers| handlers.borrow_mut().actions.remove(action_id));
    }

    /// Runs `handler` for every action that has no handler of its own. For a program
    /// whose logic already has named commands, this one handler can forward them all.
    pub fn on_any_action(&self, handler: impl Fn(&ActionContext) + 'static) {
        HANDLERS.with(|handlers| handlers.borrow_mut().any_action.replace(Rc::new(handler)));
    }

    // MARK: - Application events

    pub fn on_will_finish_launching(&self, handler: impl Fn() + 'static) {
        HANDLERS.with(|handlers| handlers.borrow_mut().will_finish_launching.replace(Rc::new(handler)));
        unsafe { sys::actionUIAppSetWillFinishLaunchingHandler(Some(will_finish_launching_trampoline)) };
    }

    pub fn on_did_finish_launching(&self, handler: impl Fn() + 'static) {
        HANDLERS.with(|handlers| handlers.borrow_mut().did_finish_launching.replace(Rc::new(handler)));
        unsafe { sys::actionUIAppSetDidFinishLaunchingHandler(Some(did_finish_launching_trampoline)) };
    }

    pub fn on_will_become_active(&self, handler: impl Fn() + 'static) {
        HANDLERS.with(|handlers| handlers.borrow_mut().will_become_active.replace(Rc::new(handler)));
        unsafe { sys::actionUIAppSetWillBecomeActiveHandler(Some(will_become_active_trampoline)) };
    }

    pub fn on_did_become_active(&self, handler: impl Fn() + 'static) {
        HANDLERS.with(|handlers| handlers.borrow_mut().did_become_active.replace(Rc::new(handler)));
        unsafe { sys::actionUIAppSetDidBecomeActiveHandler(Some(did_become_active_trampoline)) };
    }

    pub fn on_will_resign_active(&self, handler: impl Fn() + 'static) {
        HANDLERS.with(|handlers| handlers.borrow_mut().will_resign_active.replace(Rc::new(handler)));
        unsafe { sys::actionUIAppSetWillResignActiveHandler(Some(will_resign_active_trampoline)) };
    }

    pub fn on_did_resign_active(&self, handler: impl Fn() + 'static) {
        HANDLERS.with(|handlers| handlers.borrow_mut().did_resign_active.replace(Rc::new(handler)));
        unsafe { sys::actionUIAppSetDidResignActiveHandler(Some(did_resign_active_trampoline)) };
    }

    /// The last chance to save anything: the process ends when the handler returns.
    pub fn on_will_terminate(&self, handler: impl Fn() + 'static) {
        HANDLERS.with(|handlers| handlers.borrow_mut().will_terminate.replace(Rc::new(handler)));
    }

    /// Asked before quitting. Return false to keep the application running.
    pub fn on_should_terminate(&self, handler: impl Fn() -> bool + 'static) {
        HANDLERS.with(|handlers| handlers.borrow_mut().should_terminate.replace(Rc::new(handler)));
        unsafe { sys::actionUIAppSetShouldTerminateHandler(Some(should_terminate_trampoline)) };
    }

    // MARK: - Window events

    /// Runs after a window's content is loaded and before the window is shown, so values
    /// set here are in place for the first frame.
    pub fn on_window_will_present(&self, handler: impl Fn(&Window) + 'static) {
        HANDLERS.with(|handlers| handlers.borrow_mut().window_will_present.replace(Rc::new(handler)));
        unsafe { sys::actionUIAppSetWindowWillPresentHandler(Some(window_will_present_trampoline)) };
    }

    pub fn on_window_will_close(&self, handler: impl Fn(&Window) + 'static) {
        HANDLERS.with(|handlers| handlers.borrow_mut().window_will_close.replace(Rc::new(handler)));
        unsafe { sys::actionUIAppSetWindowWillCloseHandler(Some(window_will_close_trampoline)) };
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn file_urls_escape_what_a_url_cannot_hold() {
        assert_eq!(file_url(Path::new("/tmp/plain.json")), "file:///tmp/plain.json");
        assert_eq!(file_url(Path::new("/tmp/My UI #1.json")), "file:///tmp/My%20UI%20%231.json");
        assert_eq!(file_url(Path::new("/tmp/\u{17c}.json")), "file:///tmp/%C5%BC.json");
    }

    #[test]
    fn the_app_cannot_be_created_off_the_main_thread() {
        assert!(matches!(App::new(), Err(Error::NotMainThread)));
        assert!(App::get().is_none());
    }

    #[test]
    fn action_context_reads_typed_context() {
        let action = ActionContext {
            action_id: "row.selected".to_string(),
            window: Window::with_uuid("W"),
            view_id: 3,
            view_part_id: 0,
            context: Some(serde_json::json!({ "row": 4 })),
        };
        let context: HashMap<String, i64> = action.context_as().unwrap().unwrap();
        assert_eq!(context["row"], 4);

        let without = ActionContext { context: None, ..action };
        assert!(without.context_as::<i64>().unwrap().is_none());
    }

    // An ActionContext is Send, so it can reach a worker thread; the token must not.
    #[test]
    #[should_panic(expected = "other than the main thread")]
    fn an_action_context_gives_no_app_off_the_main_thread() {
        let action = ActionContext {
            action_id: String::new(),
            window: Window::with_uuid("W"),
            view_id: 0,
            view_part_id: 0,
            context: None,
        };
        let _ = action.app();
    }

    // A handler being replaced can own a value whose destructor registers or removes
    // handlers (or closes a window, which runs the will-close trampoline). The old
    // handler must therefore be dropped after the table is released.
    #[test]
    fn replacing_a_handler_drops_the_old_one_outside_the_table() {
        struct RegistersOnDrop;
        impl Drop for RegistersOnDrop {
            fn drop(&mut self) {
                App::token().on_action("registered.on.drop", |_| {});
            }
        }
        let app = App::token();

        let captured = RegistersOnDrop;
        app.on_any_action(move |_| {
            let _ = &captured;
        });
        app.on_any_action(|_| {});

        let captured = RegistersOnDrop;
        app.on_action("replaced", move |_| {
            let _ = &captured;
        });
        app.on_action("replaced", |_| {});

        let captured = RegistersOnDrop;
        app.on_will_terminate(move || {
            let _ = &captured;
        });
        app.on_will_terminate(|| {});

        assert!(HANDLERS.with(|handlers| handlers.borrow().actions.contains_key("registered.on.drop")));
    }
}
