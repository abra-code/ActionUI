// ActionUIAdwaita/Viewer/main.swift
/*
 ActionUIAdwaitaViewer: opens an ActionUI document in a window on Linux, through AdwaitaApplication.

 Usage: ActionUIAdwaitaViewer <document.json> [--dark] [--screenshot <file.png>] [--rows <id> <rows.json>]...

 The document is a path, a file URL, or an http or https URL (the window appears once it loads).
 - --dark: libadwaita's dark style, whatever the desktop's.
 - --screenshot: once the window has drawn, saves it as a PNG file (drawn by the window's own
   renderer, header bar included) and quits; the exit status says whether it was written.
 - A document that cannot be loaded shows its error in the window (saved too with --screenshot),
   and the exit status is 65.
 - --rows: sets the rows of the element with that id (a List, Table or Chart) from a JSON file
   holding an array of rows, each an array of strings, as a host's setElementRows does; for
   screenshots of data. A file that cannot be read or holds no such array stops the viewer (exit
   status 66).
 Actions the document fires have no handler here; they are logged.
*/

import CAdwaita
import Dispatch
import FoundationEssentials
import Glibc
import ActionUI

let usage = "usage: ActionUIAdwaitaViewer <document.json> [--dark] [--screenshot <file.png>] [--rows <id> <rows.json>]..."
let windowUUID = "viewer"
/// How long the window has to draw before a screenshot is taken.
let screenshotDelay = DispatchTimeInterval.milliseconds(600)

var documentPath: String?
var screenshotPath: String?
var dark = false
var elementRows: [(id: Int, rows: [[String]])] = []
var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() {
    switch argument {
    case "--dark":
        dark = true
    case "--screenshot":
        guard let path = arguments.popFirst() else {
            print(usage)
            exit(64)
        }
        screenshotPath = path
    case "--rows":
        guard let id = arguments.popFirst().flatMap({ Int($0) }), let path = arguments.popFirst() else {
            print(usage)
            exit(64)
        }
        guard let data = FileManager.default.contents(atPath: path),
              let rows = (try? ActionUIJSON.value(from: String(decoding: data, as: UTF8.self))) as? [[String]] else {
            print("ActionUIAdwaitaViewer: \(path) is not a JSON array of rows of strings")
            exit(66)
        }
        elementRows.append((id, rows))
    default:
        guard documentPath == nil, !argument.hasPrefix("--") else {
            print(usage)
            exit(64)
        }
        documentPath = argument
    }
}
guard let documentPath else {
    print(usage)
    exit(64)
}

var status: Int32 = 0
/// Set when the screenshot was tried; the window can close before then, ending the application.
var screenshotTried = false
MainActor.assumeIsolated {
    let app = AdwaitaApplication.shared
    app.name = "ActionUI Viewer"
    app.applicationID = "com.abracode.actionui.viewer"
    app.handlers.willFinishLaunching = {
        if dark {
            adw_style_manager_set_color_scheme(adw_style_manager_get_default(), ADW_COLOR_SCHEME_FORCE_DARK)
        }
    }
    // When the window appears, which an http or https document makes later than the launch.
    app.handlers.windowWillPresent = { _ in
        // A document that could not be loaded shows its error in the window; the run still fails.
        if !app.showsDocument(windowUUID) {
            print("ActionUIAdwaitaViewer: \(documentPath) could not be loaded")
            status = 65
        }
        for (id, rows) in elementRows {
            ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: id, rows: rows)
        }
        if let screenshotPath {
            DispatchQueue.main.asyncAfter(deadline: .now() + screenshotDelay) {
                screenshotTried = true
                if app.savePNG(windowUUID: windowUUID, path: screenshotPath) {
                    print("ActionUIAdwaitaViewer: saved \(screenshotPath)")
                } else {
                    print("ActionUIAdwaitaViewer: could not save \(screenshotPath)")
                    status = 1
                }
                app.terminate()
            }
        }
    }
    app.presentWindow(url: documentPath, windowUUID: windowUUID, title: nil)
    let runStatus = app.run()
    if let screenshotPath, !screenshotTried {
        print("ActionUIAdwaitaViewer: the window closed before \(screenshotPath) was saved")
        status = 1
    }
    if status == 0 {
        status = runStatus
    }
}
exit(status)
