// Runs a real application: launches, presents a window, receives an action, reads and
// writes element values, closes the window and quits, checking that each handler ran.
//
// It needs a window server and an awake display, so it only runs on request:
//
//   ACTIONUI_GUI_TESTS=1 cargo test -p actionui --test window_lifecycle
//
// Quitting ends the process from inside the event loop, so the checks are evaluated in
// the will-terminate handler, which sets the exit status.

use std::cell::{Cell, RefCell};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;
use std::thread;
use std::time::Duration;

use actionui::{ActionContext, App, Error, Window, main_thread};

const UI: &str = include_str!("fixtures/lifecycle.json");

const INPUT: i64 = 10;
const UNIT: i64 = 20;
const OUTPUT: i64 = 40;
const NO_SUCH_VIEW: i64 = 987_654;

const WATCHDOG: Duration = Duration::from_secs(30);

static CLOSURE_AFTER_PANIC_RAN: AtomicBool = AtomicBool::new(false);

#[derive(Default)]
struct Seen {
    will_finish_launching: Cell<bool>,
    did_finish_launching: Cell<bool>,
    presented: RefCell<Option<Window>>,
    will_present: RefCell<Option<Window>>,
    will_close: RefCell<Option<Window>>,
    should_terminate: Cell<bool>,
    appeared: RefCell<Option<ActionContext>>,
    unhandled: RefCell<Vec<String>>,
    failures: RefCell<Vec<String>>,
}

// Everything here happens on the main thread, so the record of what was seen lives in
// that thread's storage. The closures handed to timers then carry nothing that is not Send.
thread_local! {
    static SEEN: Seen = Seen::default();
}

fn check(what: &str, passed: bool) {
    println!("  {} {what}", if passed { "ok  " } else { "FAIL" });
    if !passed {
        SEEN.with(|seen| seen.failures.borrow_mut().push(what.to_string()));
    }
}

/// Runs `work` on the main thread after `delay`.
fn later(delay: Duration, work: impl FnOnce() + Send + 'static) {
    thread::spawn(move || {
        thread::sleep(delay);
        main_thread::dispatch(work);
    });
}

fn check_values(window: &Window) {
    // Set in the will-present handler, before the first frame.
    // The text field has keyboard focus, so typing while the test runs changes it; the
    // value read is printed to tell that apart from a real failure.
    let input = window.get_string(INPUT);
    check(&format!("a value set before presentation is read back (read {input:?})"), matches!(&input, Ok(Some(text)) if text == "100"));

    let unit = window.get_string(UNIT);
    check("a Picker reports a tag", matches!(&unit, Ok(Some(tag)) if tag == "C" || tag == "F"));

    check("an unknown view has no value and is not an error", matches!(window.get_string(NO_SUCH_VIEW), Ok(None)));
    check("reading a string as a boolean is an error", matches!(window.get_bool(INPUT), Err(Error::ActionUI(_))));

    let generic: actionui::Result<Option<serde_json::Value>> = window.get_value(INPUT);
    check(&format!("the generic getter returns the same value as JSON (read {generic:?})"), matches!(&generic, Ok(Some(value)) if value == "100"));

    check("a string with a zero byte is refused", matches!(window.set_string(OUTPUT, "a\0b"), Err(Error::InteriorNul(_))));
    check("the generic setter accepts a string", window.set_value(OUTPUT, "from Rust").is_ok());

    let limits = window.content_size_limits();
    check("the content reports its minimum size", matches!(limits, Ok(Some(limits)) if limits.min_width >= 320.0));

    // A call from another thread is refused instead of being run there.
    let (sender, receiver) = mpsc::channel();
    let worker_window = window.clone();
    thread::spawn(move || {
        let _ = sender.send(matches!(worker_window.get_string(INPUT), Err(Error::NotMainThread)));
    });
    check("a call from a worker thread is refused", receiver.recv_timeout(Duration::from_secs(5)) == Ok(true));
}

fn check_written_value(window: &Window) {
    // Setters are queued, so the value is read back on a later turn of the event loop.
    check("a value written by the generic setter is read back", window.get_string(OUTPUT).ok().flatten().as_deref() == Some("from Rust"));
}

fn check_at_termination() {
    SEEN.with(|seen| {
        check("will-finish-launching ran", seen.will_finish_launching.get());
        check("did-finish-launching ran", seen.did_finish_launching.get());
        check("should-terminate was asked", seen.should_terminate.get());

        let presented = seen.presented.borrow().clone();
        check("the will-present handler named the new window", presented.is_some() && presented == *seen.will_present.borrow());
        check("the will-close handler named the same window", presented.is_some() && presented == *seen.will_close.borrow());

        let appeared = seen.appeared.borrow().clone();
        check(
            "the on-appear action arrived with its window and view",
            matches!(&appeared, Some(action) if action.action_id == "test.appeared" && Some(&action.window) == presented.as_ref() && action.view_id == OUTPUT),
        );
        check("no action went to the catch-all handler", seen.unhandled.borrow().is_empty());
        check("the application survived a panicking closure", CLOSURE_AFTER_PANIC_RAN.load(Ordering::SeqCst));
    });
}

fn main() {
    if std::env::var_os("ACTIONUI_GUI_TESTS").is_none() {
        println!("window_lifecycle: skipped (set ACTIONUI_GUI_TESTS=1 to run; it opens a window)");
        return;
    }

    thread::spawn(|| {
        thread::sleep(WATCHDOG);
        eprintln!("window_lifecycle: FAILED, the application did not quit within {WATCHDOG:?}");
        std::process::exit(2);
    });

    let app = App::new().expect("App::new on the main thread");
    assert!(matches!(App::new(), Err(Error::AppAlreadyCreated)), "a second App::new must fail");
    assert!(App::get().is_some());
    app.set_name("ActionUI Rust Test").expect("set_name");
    println!("ActionUI {}", actionui::version());

    app.on_will_finish_launching(|| SEEN.with(|seen| seen.will_finish_launching.set(true)));

    app.on_window_will_present(|window| {
        let _ = window.set_string(INPUT, "100");
        SEEN.with(|seen| *seen.will_present.borrow_mut() = Some(window.clone()));
    });

    app.on_window_will_close(|window| SEEN.with(|seen| *seen.will_close.borrow_mut() = Some(window.clone())));

    app.on_action("test.appeared", |action| SEEN.with(|seen| *seen.appeared.borrow_mut() = Some(action.clone())));
    app.on_any_action(|action| SEEN.with(|seen| seen.unhandled.borrow_mut().push(action.action_id.clone())));

    app.on_should_terminate(|| {
        SEEN.with(|seen| seen.should_terminate.set(true));
        true
    });

    app.on_did_finish_launching(move || {
        SEEN.with(|seen| seen.did_finish_launching.set(true));
        let window = app.present_window_from_json(UI, "Lifecycle Test").expect("present_window_from_json");
        SEEN.with(|seen| *seen.presented.borrow_mut() = Some(window.clone()));

        // A panic in a dispatched closure must not take the application down.
        main_thread::dispatch(|| panic!("expected in this test"));
        main_thread::dispatch(|| CLOSURE_AFTER_PANIC_RAN.store(true, Ordering::SeqCst));

        let for_values = window.clone();
        later(Duration::from_millis(1000), move || check_values(&for_values));
        let for_written = window.clone();
        later(Duration::from_millis(1300), move || check_written_value(&for_written));
        later(Duration::from_millis(1600), move || {
            let _ = window.close();
        });
        later(Duration::from_millis(2000), || {
            if let Some(app) = App::get() {
                app.terminate();
            }
        });
    });

    app.on_will_terminate(|| {
        check_at_termination();
        let failed = SEEN.with(|seen| seen.failures.borrow().len());
        if failed == 0 {
            println!("window_lifecycle: passed");
        } else {
            eprintln!("window_lifecycle: FAILED ({failed} checks)");
            std::process::exit(1);
        }
    });

    app.run()
}
