// The host's trust policy (set_trust_policy) and element origins (Window::element_origin),
// against a real window, as ActionUIPython/test_trust_policy.py checks them.
//
// One window loaded from a temporary folder, outside the app's resources (this crate's
// folder, named explicitly):
// - root.json, the window's own document, is made trusted by the policy, as a host trusts a
//   document it chose itself;
// - less.json, in its first LoadableView, keeps ActionUI's own decision, less trusted; its
//   Image reads a file there, which reaches the policy's allows with a refusal as the default;
// - trusted.json, in the second, is made trusted by the policy.
//
// It needs a window server (macOS) or a display (Linux), so it only runs on request:
//
//   ACTIONUI_GUI_TESTS=1 cargo test -p actionui --test trust_policy

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::thread;
use std::time::Duration;

use actionui::{App, Capability, Origin, Source, Trust, TrustPolicy, main_thread};

const WATCHDOG: Duration = Duration::from_secs(20);

static TRUST_CALLS: Mutex<Vec<(Source, Option<Origin>, Trust)>> = Mutex::new(Vec::new());
static ALLOWS_CALLS: Mutex<Vec<(Capability, Origin, bool)>> = Mutex::new(Vec::new());
static ORIGINS: Mutex<BTreeMap<i64, Option<Origin>>> = Mutex::new(BTreeMap::new());
static FAILURES: Mutex<Vec<String>> = Mutex::new(Vec::new());

fn check(what: &str, passed: bool) {
    println!("  {} {what}", if passed { "ok  " } else { "FAIL" });
    if !passed {
        FAILURES.lock().unwrap().push(what.to_string());
    }
}

fn path_of(source: &Source) -> &str {
    match source {
        Source::File { path } | Source::Resource { path } => path,
        _ => "",
    }
}

struct RecordingPolicy;

impl TrustPolicy for RecordingPolicy {
    fn trust(&self, source: &Source, parent: Option<&Origin>, by_default: Trust) -> Trust {
        TRUST_CALLS.lock().unwrap().push((source.clone(), parent.cloned(), by_default));
        let path = path_of(source);
        if path.ends_with("root.json") || path.ends_with("trusted.json") { Trust::Trusted } else { by_default }
    }

    fn allows(&self, capability: &Capability, origin: &Origin, by_default: bool) -> bool {
        ALLOWS_CALLS.lock().unwrap().push((capability.clone(), origin.clone(), by_default));
        by_default
    }
}

/// A valid 1x1 RGBA PNG, stored uncompressed (zlib's stored block).
fn png() -> Vec<u8> {
    fn crc32(bytes: &[u8]) -> u32 {
        let mut crc = !0u32;
        for byte in bytes {
            crc ^= u32::from(*byte);
            for _ in 0..8 {
                crc = (crc >> 1) ^ (0xedb8_8320 & 0u32.wrapping_sub(crc & 1));
            }
        }
        !crc
    }
    fn adler32(bytes: &[u8]) -> u32 {
        let (mut a, mut b) = (1u32, 0u32);
        for byte in bytes {
            a = (a + u32::from(*byte)) % 65521;
            b = (b + a) % 65521;
        }
        (b << 16) | a
    }
    fn chunk(out: &mut Vec<u8>, kind: &[u8], data: &[u8]) {
        out.extend_from_slice(&(data.len() as u32).to_be_bytes());
        let mut body = kind.to_vec();
        body.extend_from_slice(data);
        out.extend_from_slice(&body);
        out.extend_from_slice(&crc32(&body).to_be_bytes());
    }
    let row = [0u8, 255, 0, 0, 255];
    let mut zlib = vec![0x78, 0x01, 0x01];
    zlib.extend_from_slice(&(row.len() as u16).to_le_bytes());
    zlib.extend_from_slice(&(!(row.len() as u16)).to_le_bytes());
    zlib.extend_from_slice(&row);
    zlib.extend_from_slice(&adler32(&row).to_be_bytes());
    let mut header = Vec::new();
    header.extend_from_slice(&1u32.to_be_bytes());
    header.extend_from_slice(&1u32.to_be_bytes());
    header.extend_from_slice(&[8, 6, 0, 0, 0]);
    let mut out = vec![0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a];
    chunk(&mut out, b"IHDR", &header);
    chunk(&mut out, b"IDAT", &zlib);
    chunk(&mut out, b"IEND", &[]);
    out
}

fn write_json_files() -> PathBuf {
    let folder = std::env::temp_dir().join(format!("actionui-trust-rust-{}", std::process::id()));
    std::fs::create_dir_all(&folder).expect("temporary folder");
    let picture = folder.join("pic.png");
    std::fs::write(&picture, png()).expect("picture");
    let file = |name: &str| folder.join(name).display().to_string();
    std::fs::write(folder.join("less.json"), format!(
        r#"{{"type": "VStack", "id": 20, "children": [{{"type": "Image", "id": 21, "properties": {{"filePath": "{}"}}}}]}}"#,
        picture.display())).expect("less.json");
    std::fs::write(folder.join("trusted.json"), r#"{"type": "Text", "id": 30, "properties": {"text": "Trusted by the host"}}"#).expect("trusted.json");
    std::fs::write(folder.join("root.json"), format!(
        r#"{{"type": "VStack", "id": 1, "children": [{{"type": "LoadableView", "id": 3, "properties": {{"filePath": "{}"}}}}, {{"type": "LoadableView", "id": 4, "properties": {{"filePath": "{}"}}}}]}}"#,
        file("less.json"), file("trusted.json"))).expect("root.json");
    folder
}

fn later(delay: Duration, work: impl FnOnce() + Send + 'static) {
    thread::spawn(move || {
        thread::sleep(delay);
        main_thread::dispatch(work);
    });
}

fn check_at_termination() {
    let origins = ORIGINS.lock().unwrap().clone();
    let root = origins.get(&1).cloned().flatten();
    check("the window's own document is a file, trusted by the policy, with no parent",
        matches!(&root, Some(Origin { source: Source::File { path }, trust: Trust::Trusted, parent_id: None }) if path.ends_with("root.json")));
    check("less.json is a file, less trusted, inside LoadableView 3",
        matches!(origins.get(&20), Some(Some(Origin { source: Source::File { path }, trust: Trust::LessTrusted, parent_id: Some(3) })) if path.ends_with("less.json")));
    check("trusted.json is trusted by the policy",
        matches!(origins.get(&30), Some(Some(Origin { trust: Trust::Trusted, parent_id: Some(4), .. }))));
    check("an element the window does not have has no origin", matches!(origins.get(&999), Some(None)));
    let calls = TRUST_CALLS.lock().unwrap().clone();
    check("the policy was asked for both documents",
        calls.iter().any(|call| path_of(&call.0).ends_with("less.json")) && calls.iter().any(|call| path_of(&call.0).ends_with("trusted.json")));
    check("every call had less trusted as the default (all are outside the resources)",
        !calls.is_empty() && calls.iter().all(|call| call.2 == Trust::LessTrusted));
    check("the window's document had no parent, the LoadableViews' the trusted root",
        calls.iter().all(|call| (call.1.is_none() == path_of(&call.0).ends_with("root.json")) && (call.1.is_none() || call.1 == root)));
    let reads: Vec<_> = ALLOWS_CALLS.lock().unwrap().iter()
        .filter(|call| matches!(&call.0, Capability::ReadLocalFile { path } if path.ends_with("pic.png")))
        .cloned().collect();
    check("allows was asked about less.json's picture, refused by default",
        !reads.is_empty() && reads.iter().all(|call| call.1.trust == Trust::LessTrusted && !call.2));
}

fn main() {
    if std::env::var_os("ACTIONUI_GUI_TESTS").is_none() {
        println!("trust_policy: skipped (set ACTIONUI_GUI_TESTS=1 to run; it opens a window)");
        return;
    }
    thread::spawn(|| {
        thread::sleep(WATCHDOG);
        eprintln!("trust_policy: FAILED, the application did not quit within {WATCHDOG:?}");
        std::process::exit(2);
    });

    let folder = write_json_files();
    let app = App::new().expect("App::new on the main thread");
    // The temporary folder is outside the resources wherever the test runs from.
    app.set_resource_folder(Some(Path::new(env!("CARGO_MANIFEST_DIR")))).expect("set_resource_folder");
    actionui::set_trust_policy(RecordingPolicy);

    app.on_window_will_close(|window| {
        let mut origins = ORIGINS.lock().unwrap();
        for view_id in [1, 20, 30, 999] {
            origins.insert(view_id, window.element_origin(view_id).unwrap_or(None));
        }
    });
    app.on_should_terminate(|| true);
    app.on_did_finish_launching(move || {
        let window = app.present_window_from_file(folder.join("root.json"), Some("Trust Policy Test")).expect("present_window_from_file");
        later(Duration::from_millis(1500), move || {
            let _ = window.close();
        });
        later(Duration::from_millis(2000), || {
            if let Some(app) = App::get() {
                app.terminate();
            }
        });
    });
    app.on_will_terminate(|| {
        actionui::clear_trust_policy();
        check_at_termination();
        let failed = FAILURES.lock().unwrap().len();
        if failed == 0 {
            println!("trust_policy: passed");
        } else {
            eprintln!("trust_policy: FAILED ({failed} checks)");
            std::process::exit(1);
        }
    });
    app.run()
}
