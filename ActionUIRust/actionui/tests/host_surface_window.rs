// Runs a real application with a HostSurface element and checks the binding rules through the
// Rust API: a delegate gets "created" with a Metal layer (macOS) or a frame sink (Linux); hidden
// and padding changes do not destroy the surface; a delegate bound inside a callback takes over
// after it, with "destroyed" first, also when bound inside the "destroyed" of a delegate being
// replaced; an unbound delegate gets "destroyed"; closing the window destroys the surface.
//
// It needs a window server, so it only runs on request (a locked screen is fine: the surface is
// created and then suspended as occluded):
//
//   ACTIONUI_GUI_TESTS=1 cargo test -p actionui --features host-surface --test host_surface_window
//
// Quitting ends the process from inside the event loop, so the checks are evaluated in the
// will-terminate handler, which sets the exit status.

use std::cell::RefCell;
use std::thread;
use std::time::Duration;

use actionui::host_surface::{SurfaceDelegate, SurfaceHandle, SurfaceInfo};
use actionui::{App, Window, main_thread};

const UI: &str = r#"{ "type": "VStack", "id": 1, "children": [
    { "type": "Text", "id": 2, "properties": { "text": "HostSurface test" } },
    { "type": "HostSurface", "id": 5, "properties": { "surfaceName": "test.canvas", "idealWidth": 200, "idealHeight": 120 } }
] }"#;

const CANVAS: i64 = 5;
const WATCHDOG: Duration = Duration::from_secs(30);

/// One event a delegate received: who, what, which surface, how many pixels.
#[derive(Clone, Debug)]
struct Event {
    delegate: &'static str,
    event: &'static str,
    surface: u64,
    pixels: (u32, u32),
    /// The platform's handle: a Metal layer on macOS, a frame sink on Linux.
    native_handle: bool,
}

thread_local! {
    static EVENTS: RefCell<Vec<Event>> = const { RefCell::new(Vec::new()) };
    static FAILURES: RefCell<Vec<String>> = const { RefCell::new(Vec::new()) };
}

fn check(what: &str, passed: bool) {
    println!("  {} {what}", if passed { "ok  " } else { "FAIL" });
    if !passed {
        FAILURES.with(|failures| failures.borrow_mut().push(what.to_string()));
    }
}

fn later(delay: Duration, work: impl FnOnce() + Send + 'static) {
    thread::spawn(move || {
        thread::sleep(delay);
        main_thread::dispatch(work);
    });
}

fn events() -> Vec<Event> {
    EVENTS.with(|events| events.borrow().clone())
}

fn names(delegate: &str) -> Vec<&'static str> {
    events().iter().filter(|event| event.delegate == delegate).map(|event| event.event).collect()
}

/// Records what it is told. With `hand_over`, it binds the delegate "second" in its first "created".
/// With `rebind_in_destroyed`, its first "destroyed" binds a delegate of that name.
struct Recorder {
    name: &'static str,
    hand_over: bool,
    rebind_in_destroyed: Option<&'static str>,
}

impl Recorder {
    fn record(&self, event: &'static str, info: &SurfaceInfo) {
        let native_handle = if cfg!(target_os = "macos") {
            matches!(info.handle, SurfaceHandle::MetalLayer(_))
        } else {
            info.handle == SurfaceHandle::FrameSink
        };
        EVENTS.with(|events| {
            events.borrow_mut().push(Event {
                delegate: self.name,
                event,
                surface: info.id.get(),
                pixels: (info.width_pixels, info.height_pixels),
                native_handle,
            })
        });
    }
}

impl SurfaceDelegate for Recorder {
    fn created(&mut self, info: &SurfaceInfo) {
        self.record("created", info);
        if self.hand_over {
            self.hand_over = false;
            let app = App::get().expect("the main thread");
            let bound = app.set_surface_delegate("test.canvas", Recorder { name: "second", hand_over: false, rebind_in_destroyed: None });
            check("a delegate can be bound inside a callback", bound.is_ok());
            // The change waits until this callback returns.
            check("the new delegate is not called inside the old one's callback", names("second").is_empty());
        }
    }
    fn changed(&mut self, info: &SurfaceInfo) {
        self.record("changed", info);
    }
    fn suspended(&mut self, info: &SurfaceInfo) {
        self.record("suspended", info);
    }
    fn resumed(&mut self, info: &SurfaceInfo) {
        self.record("resumed", info);
    }
    fn destroyed(&mut self, info: &SurfaceInfo) {
        self.record("destroyed", info);
        if let Some(name) = self.rebind_in_destroyed.take() {
            let app = App::get().expect("the main thread");
            let bound = app.set_surface_delegate("test.canvas", Recorder { name, hand_over: false, rebind_in_destroyed: None });
            check("a delegate can be bound inside the destroyed of a replaced one", bound.is_ok());
        }
    }
}

fn check_created() {
    let first = names("first");
    check(&format!("the first delegate got created, then destroyed when it handed over (got {first:?})"),
        first.first() == Some(&"created") && first.last() == Some(&"destroyed")
            && first.iter().filter(|name| **name == "created").count() == 1);
    let all = events();
    let created = all.iter().find(|event| event.delegate == "second" && event.event == "created");
    check("the second delegate got created", created.is_some());
    if let Some(created) = created {
        check("with a Metal layer (macOS) or a frame sink (Linux)", created.native_handle);
        check(&format!("and a nonzero pixel size (got {:?})", created.pixels), created.pixels.0 > 0 && created.pixels.1 > 0);
        let first_destroyed = all.iter().position(|event| event.delegate == "first" && event.event == "destroyed");
        let second_created = all.iter().position(|event| event.delegate == "second" && event.event == "created");
        check("destroyed for the old delegate came before created for the new one", first_destroyed < second_created);
        let first_id = all.iter().find(|event| event.delegate == "first").map(|event| event.surface);
        check("the new delegate got a new surface ID", first_id != Some(created.surface));
    }
}

fn check_no_destroy_after_changes() {
    let second = names("second");
    check(&format!("hidden and padding changes did not destroy the surface (got {second:?})"),
        !second.contains(&"destroyed") && second.iter().filter(|name| **name == "created").count() == 1);
}

thread_local! {
    /// The window the Closer closes, and what the Closer was told.
    static CLOSER_WINDOW: RefCell<Option<Window>> = const { RefCell::new(None) };
    static CLOSER_LOG: RefCell<Vec<&'static str>> = const { RefCell::new(Vec::new()) };
}

/// Closes its window inside "created": the "destroyed" that causes must arrive after "created" returns,
/// not be lost.
struct Closer {
    inside_created: bool,
}

impl SurfaceDelegate for Closer {
    fn created(&mut self, _info: &SurfaceInfo) {
        CLOSER_LOG.with(|log| log.borrow_mut().push("created"));
        self.inside_created = true;
        if let Some(window) = CLOSER_WINDOW.with(|window| window.borrow().clone()) {
            let _ = window.close();
        }
        self.inside_created = false;
    }
    fn destroyed(&mut self, _info: &SurfaceInfo) {
        check("destroyed does not run inside the created that caused it", !self.inside_created);
        CLOSER_LOG.with(|log| log.borrow_mut().push("destroyed"));
    }
}

const CLOSER_UI: &str = r#"{ "type": "HostSurface", "id": 7, "properties": { "surfaceName": "test.closer", "idealWidth": 120, "idealHeight": 80 } }"#;

fn main() {
    if std::env::var_os("ACTIONUI_GUI_TESTS").is_none() {
        println!("host_surface_window: skipped (set ACTIONUI_GUI_TESTS=1 to run it)");
        return;
    }
    thread::spawn(|| {
        thread::sleep(WATCHDOG);
        eprintln!("host_surface_window: FAILED, the application did not quit within {WATCHDOG:?}");
        std::process::exit(2);
    });

    let app = App::new().expect("App::new on the main thread");
    app.set_name("ActionUI HostSurface Test").expect("set_name");
    app.set_surface_delegate("test.canvas", Recorder { name: "first", hand_over: true, rebind_in_destroyed: None }).expect("set_surface_delegate");

    app.on_did_finish_launching(move || {
        let window = app.present_window_from_json(UI, Some("HostSurface Test")).expect("present_window_from_json");
        let toggles: Window = window.clone();
        later(Duration::from_millis(1000), move || {
            check_created();
            let _ = toggles.set_property(CANVAS, "hidden", &true);
            let _ = toggles.set_property(CANVAS, "padding", &20);
        });
        let toggles = window.clone();
        later(Duration::from_millis(1500), move || {
            let _ = toggles.set_property(CANVAS, "hidden", &false);
        });
        later(Duration::from_millis(2000), || {
            check_no_destroy_after_changes();
            let app = App::get().expect("the main thread");
            check("the delegate is unbound", app.remove_surface_delegate("test.canvas").is_ok());
            check("and gets destroyed at once", names("second").last() == Some(&"destroyed"));
            check("binding again", app.set_surface_delegate("test.canvas", Recorder { name: "third", hand_over: false, rebind_in_destroyed: Some("fifth") }).is_ok());
            check("announces the live surface at once", names("third").first() == Some(&"created"));
        });
        later(Duration::from_millis(2200), || {
            // "third" binds "fifth" inside the destroyed this call sends it: the later binding wins.
            let app = App::get().expect("the main thread");
            let bound = app.set_surface_delegate("test.canvas", Recorder { name: "fourth", hand_over: false, rebind_in_destroyed: None });
            check("binding over a delegate that binds again in its destroyed", bound.is_ok());
            check(&format!("the replaced delegate got destroyed (got {:?})", names("third")), names("third").last() == Some(&"destroyed"));
            check(&format!("the binding made inside it took over (fourth {:?}, fifth {:?})", names("fourth"), names("fifth")),
                names("fourth").first() == Some(&"created") && names("fourth").last() == Some(&"destroyed")
                    && names("fifth").first() == Some(&"created") && !names("fifth").contains(&"destroyed"));
        });
        later(Duration::from_millis(2400), move || {
            let _ = window.close();
        });
        later(Duration::from_millis(2600), || {
            let app = App::get().expect("the main thread");
            if let Ok(window) = app.present_window_from_json(CLOSER_UI, Some("Closer")) {
                CLOSER_WINDOW.with(|slot| *slot.borrow_mut() = Some(window));
            }
        });
        // Bound once the window is up: the replayed "created" closes it.
        later(Duration::from_millis(3000), || {
            let app = App::get().expect("the main thread");
            let _ = app.set_surface_delegate("test.closer", Closer { inside_created: false });
        });
        later(Duration::from_millis(3600), || {
            let told = CLOSER_LOG.with(|log| log.borrow().clone());
            check(&format!("a window closed inside created still sends destroyed, after it (got {told:?})"),
                told == ["created", "destroyed"]);
            check(&format!("closing the window destroyed the surface (got {:?})", names("fifth")),
                names("fifth").last() == Some(&"destroyed"));
            if let Some(app) = App::get() {
                app.terminate();
            }
        });
    });

    app.on_will_terminate(|| {
        let failed = FAILURES.with(|failures| failures.borrow().len());
        if failed == 0 {
            println!("host_surface_window: passed");
        } else {
            eprintln!("host_surface_window: FAILED ({failed} checks)");
            std::process::exit(1);
        }
    });

    app.run()
}
