// Runs a real application: launches, loads a menu bar, presents a window, receives an
// action, reads and writes element values, rows, properties and structure from the main
// thread and from a worker, closes the window and quits, checking that each handler ran.
//
// It needs a window server and an awake display, so it only runs on request:
//
//   ACTIONUI_GUI_TESTS=1 cargo test -p actionui --test window_lifecycle
//
// Quitting ends the process from inside the event loop, so the checks are evaluated in
// the will-terminate handler, which sets the exit status.

use std::cell::{Cell, RefCell};
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::Duration;

use actionui::{ActionContext, App, Error, InsertPosition, Window, main_thread};

const UI: &str = include_str!("fixtures/lifecycle.json");

const MENU_BAR: &str = r#"[
  { "type": "CommandMenu", "properties": { "name": "Tools" },
    "children": [
      { "type": "Button", "properties": { "title": "Run Report", "actionID": "test.report" } }
    ] }
]"#;

const INPUT: i64 = 10;
const UNIT: i64 = 20;
const OUTPUT: i64 = 40;
const TABLE: i64 = 50;
const ROOT: i64 = 60;
const BUTTON: i64 = 70;
const INSERTED: i64 = 80;
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
    worker_reported: Cell<bool>,
    failures: RefCell<Vec<String>>,
}

// The checks all run on the main thread, so the record of what was seen lives in that
// thread's storage. The closures handed to timers then carry nothing that is not Send.
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
    // Set in the will-present handler, before the first frame. The text field has keyboard
    // focus, so typing while the test runs changes it; the value read is printed to tell
    // that apart from a real failure.
    let input = window.get_string(INPUT);
    check(&format!("a value set before presentation is read back (read {input:?})"), matches!(&input, Ok(Some(text)) if text == "100"));

    let unit = window.get_string(UNIT);
    check("a Picker reports a tag", matches!(&unit, Ok(Some(tag)) if tag == "C" || tag == "F"));

    check("an unknown view has no value and is not an error", matches!(window.get_string(NO_SUCH_VIEW), Ok(None)));
    check("reading a string as a boolean is an error", matches!(window.get_bool(INPUT), Err(Error::ActionUI(_))));
    check("and the next successful read is not", matches!(window.get_string(INPUT), Ok(Some(_))));

    let generic: actionui::Result<Option<serde_json::Value>> = window.get_value(INPUT);
    check(&format!("the generic getter returns the same value as JSON (read {generic:?})"), matches!(&generic, Ok(Some(value)) if value == "100"));

    let as_text = window.get_value_as_string(INPUT, None);
    check(&format!("the value is read as text (read {as_text:?})"), matches!(&as_text, Ok(Some(text)) if text == "100"));

    check("a string with a zero byte is refused", matches!(window.set_string(OUTPUT, "a\0b"), Err(Error::InteriorNul(_))));
    check("the generic setter accepts a string", window.set_value(OUTPUT, "from Rust").is_ok());

    let limits = window.content_size_limits();
    check("the content reports its minimum size", matches!(limits, Ok(Some(limits)) if limits.min_width >= 320.0));
}

fn check_structure(window: &Window) {
    let info = window.element_info().unwrap_or_default();
    check(
        "the element list names the elements with IDs",
        info.get(&INPUT).map(String::as_str) == Some("TextField") && info.get(&TABLE).map(String::as_str) == Some("Table"),
    );

    check("a Table reports its columns", matches!(window.column_count(TABLE), Ok(2)));
    check("rows are accepted", window.set_rows(TABLE, &[["Water", "C"], ["Steel", "K"]]).is_ok());
    check("more rows are accepted", window.append_rows(TABLE, &vec![vec!["Air".to_string(), "F".to_string()]]).is_ok());

    let title: actionui::Result<Option<String>> = window.get_property(BUTTON, "title");
    check(&format!("a property is read (read {title:?})"), matches!(&title, Ok(Some(title)) if title == "Convert"));
    check("a property is accepted", window.set_property(BUTTON, "title", "Converted").is_ok());

    let element = serde_json::json!({ "type": "Text", "id": INSERTED, "properties": { "text": "Inserted from Rust" } });
    let inserted = window.insert_element(ROOT, &element, None, InsertPosition::Append);
    check(&format!("an element is inserted (got {inserted:?})"), matches!(inserted, Ok(INSERTED)));
    // An element without an "id" gets a negative one from ActionUI; -1 is among them.
    let unnamed = window.insert_element(ROOT, &serde_json::json!({ "type": "Text", "properties": { "text": "No ID" } }), None, InsertPosition::Append);
    check(&format!("an element without an ID is inserted (got {unnamed:?})"), matches!(unnamed, Ok(id) if id < 0));
    if let Ok(id) = unnamed {
        check("and removed by the ID it was given", window.remove_element(id).is_ok());
    }
    let orphan = window.insert_element(NO_SUCH_VIEW, &serde_json::json!({ "type": "Text" }), None, InsertPosition::Append);
    check(&format!("inserting under an unknown parent is an error (got {orphan:?})"), matches!(orphan, Err(Error::ActionUI(_))));

    check("a toast is accepted", window.present_toast("Saved", Duration::from_secs(1), Some(("Undo", "test.undo"))).is_ok());
}

// On a later turn of the event loop, when what was queued above has been applied.
fn check_what_was_written(window: &Window) {
    check("a value written by the generic setter is read back", window.get_string(OUTPUT).ok().flatten().as_deref() == Some("from Rust"));

    let rows: actionui::Result<Option<Vec<Vec<String>>>> = window.get_rows(TABLE);
    check(
        &format!("the rows are read back (read {rows:?})"),
        matches!(&rows, Ok(Some(rows)) if rows.len() == 3 && rows[1] == ["Steel", "K"] && rows[2] == ["Air", "F"]),
    );

    check("a row is selected by content", matches!(window.select_row_with_content(TABLE, "Steel", None), Ok(Some(1))));
    check("a missing row is not selected", matches!(window.select_row_with_content(TABLE, "Gold", Some(0)), Ok(None)));
    check("a row is selected by index", matches!(window.select_row(TABLE, 2), Ok(true)));
    check("an index outside the rows selects nothing", matches!(window.select_row(TABLE, 99), Ok(false)));

    let title: actionui::Result<Option<String>> = window.get_property(BUTTON, "title");
    check(&format!("the changed property is read back (read {title:?})"), matches!(&title, Ok(Some(title)) if title == "Converted"));

    let info = window.element_info().unwrap_or_default();
    check("the inserted element is in the element list", info.get(&INSERTED).map(String::as_str) == Some("Text"));
    check("the inserted element is removed", window.remove_element(INSERTED).is_ok());
    let again = window.remove_element(INSERTED);
    check(&format!("removing it again is an error (got {again:?})"), matches!(again, Err(Error::ActionUI(_))));
}

/// Calls from a worker thread, made while the main thread is free to serve them.
fn check_from_a_worker(window: Window) {
    thread::spawn(move || {
        let read = window.get_string(INPUT);
        let wrong_type = window.get_bool(INPUT);
        let set = window.set_string(OUTPUT, "from a worker");
        // The setter is queued on the main thread ahead of this getter.
        let read_back = window.get_string(OUTPUT);
        // This error is recorded on the main thread, inside the call made for the worker.
        let removed = window.remove_element(NO_SUCH_VIEW);
        main_thread::dispatch(move || {
            check(
                &format!("a worker thread gets an error recorded on the main thread for it (got {removed:?})"),
                matches!(&removed, Err(Error::ActionUI(message)) if message.contains("987654")),
            );
            check(&format!("a worker thread reads a value (read {read:?})"), matches!(&read, Ok(Some(text)) if text == "100"));
            check(
                &format!("a worker thread gets the error of its own call (got {wrong_type:?})"),
                matches!(&wrong_type, Err(Error::ActionUI(message)) if message.contains("boolean")),
            );
            check("a worker thread sets a value", set.is_ok());
            check(&format!("and reads it back (read {read_back:?})"), matches!(&read_back, Ok(Some(text)) if text == "from a worker"));
            SEEN.with(|seen| seen.worker_reported.set(true));
        });
    });
}

fn check_remote_server(app: App) {
    let endpoint = app.start_remote_server(None);
    check(&format!("the remote server starts (got {endpoint:?})"), matches!(&endpoint, Ok(path) if !path.is_empty()));
    check("it reports the same socket path", app.remote_server_endpoint() == endpoint.as_ref().ok().cloned());
    check("it exports the socket path for child processes", std::env::var("ACTIONUI_REMOTE_ENDPOINT").ok() == endpoint.ok());
    check("it has a token", app.remote_server_token().is_some_and(|token| !token.is_empty()));
    check("a second start is an error", app.start_remote_server(None).is_err());
    app.stop_remote_server();
    check("after stopping it reports no socket path", app.remote_server_endpoint().is_none());
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
        check("the worker thread's results came back", seen.worker_reported.get());
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

    // Not before run(): with a name set, the menu bar is rebuilt as the application launches.
    app.on_will_finish_launching(move || {
        app.load_menu_bar(MENU_BAR).expect("load_menu_bar");
        SEEN.with(|seen| seen.will_finish_launching.set(true));
    });

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
        let window = app.present_window_from_json(UI, Some("Lifecycle Test")).expect("present_window_from_json");
        SEEN.with(|seen| *seen.presented.borrow_mut() = Some(window.clone()));
        check_remote_server(app);

        // A panic in a dispatched closure must not take the application down.
        main_thread::dispatch(|| panic!("expected in this test"));
        main_thread::dispatch(|| CLOSURE_AFTER_PANIC_RAN.store(true, Ordering::SeqCst));

        let for_values = window.clone();
        later(Duration::from_millis(1000), move || {
            check_values(&for_values);
            check_structure(&for_values);
        });
        let for_written = window.clone();
        later(Duration::from_millis(1400), move || check_what_was_written(&for_written));
        let for_worker = window.clone();
        later(Duration::from_millis(1800), move || check_from_a_worker(for_worker));
        later(Duration::from_millis(2600), move || {
            let _ = window.close();
        });
        later(Duration::from_millis(3000), || {
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
