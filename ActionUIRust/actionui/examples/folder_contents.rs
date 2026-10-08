// A table, a menu bar, a file panel, an alert and a worker thread in one small program:
// choose a folder and its contents are listed with their sizes.
//
//   cargo run --example folder_contents
//
// The interface and the menus are JSON files beside this one, compiled into the program.

use std::cell::RefCell;
use std::fs;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::thread;

use actionui::panels::{Alert, AlertStyle, OpenPanel};
use actionui::{App, Window, main_thread};

const UI: &str = include_str!("folder_contents.json");
const MENU_BAR: &str = include_str!("folder_contents_menu.json");

// The element IDs in the JSON.
const STATUS: i64 = 10;
const TABLE: i64 = 20;
const DETAILS: i64 = 30;

fn readable_size(bytes: u64) -> String {
    const UNITS: [&str; 4] = ["bytes", "KB", "MB", "GB"];
    let mut size = bytes as f64;
    let mut unit = 0;
    while size >= 1000.0 && unit < UNITS.len() - 1 {
        size /= 1000.0;
        unit += 1;
    }
    if unit == 0 { format!("{bytes} bytes") } else { format!("{size:.1} {}", UNITS[unit]) }
}

/// One table row for each item in the folder: name, kind, size.
fn list_folder(folder: &Path) -> std::io::Result<Vec<[String; 3]>> {
    let mut rows = Vec::new();
    for entry in fs::read_dir(folder)? {
        let entry = entry?;
        let metadata = entry.metadata()?;
        let name = entry.file_name().to_string_lossy().into_owned();
        let row = if metadata.is_dir() {
            [name, "Folder".to_string(), String::new()]
        } else {
            [name, "File".to_string(), readable_size(metadata.len())]
        };
        rows.push(row);
    }
    rows.sort_by_key(|row| row[0].to_lowercase());
    Ok(rows)
}

/// Reads the folder on a worker thread, so a slow disk does not freeze the window, and
/// fills the table from that thread. A `Window` can be used from any thread.
fn show_folder(window: &Window, folder: PathBuf) {
    let window = window.clone();
    let _ = window.set_string(STATUS, &format!("Reading {}...", folder.display()));
    thread::spawn(move || match list_folder(&folder) {
        Ok(rows) => {
            let _ = window.set_rows(TABLE, &rows);
            let _ = window.set_string(STATUS, &format!("{} - {} items", folder.display(), rows.len()));
            let _ = window.set_string(DETAILS, "");
        }
        Err(error) => {
            let _ = window.set_string(STATUS, "No folder chosen");
            // An alert needs the App, which exists only on the main thread.
            main_thread::dispatch(move || {
                if let Some(app) = App::get() {
                    let alert = Alert::new("The folder could not be read").message(format!("{}: {error}", folder.display())).style(AlertStyle::Warning);
                    let _ = alert.run(app);
                }
            });
        }
    });
}

fn main() -> actionui::Result<()> {
    let app = App::new()?;
    // A program started from an .app bundle takes its name from the bundle's Info.plist.
    if !actionui::running_from_bundle() {
        app.set_name("Folder Contents")?;
    }
    app.load_menu_bar(MENU_BAR)?;

    let window = app.present_window_from_json(UI, Some("Folder Contents"))?;
    // Handlers run on the main thread and may be entered again, so shared state that
    // changes goes in a RefCell.
    let current_folder: Rc<RefCell<Option<PathBuf>>> = Rc::new(RefCell::new(None));

    // Sent by the button in the window and by File > Open Folder... in the menu bar.
    app.on_action("folder.choose", {
        let window = window.clone();
        let current_folder = current_folder.clone();
        move |_action| {
            let panel = OpenPanel::new().title("Choose a Folder").prompt("Choose").can_choose_directories(true).can_choose_files(false);
            // Ok(None) means the panel was canceled.
            if let Ok(Some(folders)) = panel.run(app) {
                if let Some(folder) = folders.into_iter().next() {
                    current_folder.replace(Some(folder.clone()));
                    show_folder(&window, folder);
                }
            }
        }
    });

    app.on_action("folder.refresh", {
        let window = window.clone();
        let current_folder = current_folder.clone();
        move |_action| {
            let folder = current_folder.borrow().clone();
            if let Some(folder) = folder {
                show_folder(&window, folder);
            }
        }
    });

    // A Table's value is its selected row, one string for each column.
    app.on_action("folder.row.selected", move |action| {
        let details = match action.window.get_value::<Vec<String>>(TABLE) {
            Ok(Some(row)) if row.len() == 3 && row[1] == "File" => format!("{} - {}", row[0], row[2]),
            Ok(Some(row)) if !row.is_empty() => row[0].clone(),
            _ => String::new(),
        };
        let _ = action.window.set_string(DETAILS, &details);
    });

    // One window: closing it ends the program.
    app.on_window_will_close(move |_window| app.terminate());

    app.run()
}
