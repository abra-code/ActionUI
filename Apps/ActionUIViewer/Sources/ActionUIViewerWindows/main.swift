// Apps/ActionUIViewer/Sources/ActionUIViewerWindows/main.swift
/*
 ActionUIViewer: opens an ActionUI document in a window on Windows, through WinUIApplication, as
 the Linux program does through AdwaitaApplication. The add-ons are not on Windows yet.

 Usage: ActionUIViewer <document.json> [--screenshot <file.png>] [--rows <id> <rows.json>]...

 The document is a path, a file URL, or an http or https URL (the window appears once it loads).
 - --screenshot: once the window has drawn, saves what it shows below its title bar as a PNG file
   (drawn by WinUI itself) and quits; the exit status says whether it was written.
 - A document that cannot be loaded shows its error in the window (saved too with --screenshot),
   and the exit status is 65.
 - --rows: sets the rows of the element with that id (a List, Table or Chart) from a JSON file
   holding an array of rows, each an array of strings, as a host's setElementRows does; for
   screenshots of data. A file that cannot be read or holds no such array stops the viewer (exit
   status 66).
 - --dark is accepted, as on Linux, and does nothing yet: the window follows the system's theme.
 Actions the document fires have no handler here; they are logged.
*/

import Dispatch
import FoundationEssentials
import ucrt
import ActionUI
import ActionUIWinUIApplication

// Before anything loads a DLL by name: a file named like one in the current folder is never loaded.
WinUIApplication.removeCurrentFolderFromDLLSearch()

let usage = "usage: ActionUIViewer <document.json> [--screenshot <file.png>] [--rows <id> <rows.json>]..."
let windowUUID = "viewer"
/// How long the window has to draw before a screenshot is taken.
let screenshotDelay = DispatchTimeInterval.milliseconds(600)

var jsonPath: String?
var screenshotPath: String?
var elementRows: [(id: Int, rows: [[String]])] = []
var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() {
    switch argument {
    case "--dark":
        print("ActionUIViewer: --dark is not on Windows yet; the window follows the system's theme")
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
            print("ActionUIViewer: \(path) is not a JSON array of rows of strings")
            exit(66)
        }
        elementRows.append((id, rows))
    default:
        guard jsonPath == nil, !argument.hasPrefix("--") else {
            print(usage)
            exit(64)
        }
        jsonPath = argument
    }
}
guard let jsonPath else {
    print(usage)
    exit(64)
}

/// The Viewer shows the document the user names, wherever it is: that local file is trusted (no
/// less than the program's resources would be), and so is a local file it names, though never above
/// the content around it, so a remote document that names a local file keeps that file less trusted.
/// Remote documents and any other local file with no known parent keep ActionUI's default (as on
/// Linux).
struct ViewerTrustPolicy: ActionUITrustPolicy {
    /// The resolved path of the local document the user named, as JSONContentOrigin.Source.file
    /// gives it; nil for a remote document.
    let jsonPath: String?

    func trust(for source: JSONContentOrigin.Source, inside parent: JSONContentOrigin?,
               byDefault: JSONContentOrigin.Trust) -> JSONContentOrigin.Trust {
        guard case .file(let path) = source else { return byDefault }
        if let parent { return parent.trust }
        return path == jsonPath ? .trusted : byDefault
    }
}

/// The named document's path as presentWindow(url:) reads it: a file URL or a path; nil for an
/// http or https address.
let localJSONPath: String? = {
    let lowered = jsonPath.lowercased()
    if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") { return nil }
    let url: URL
    if lowered.hasPrefix("file://"), let fileURL = URL(string: jsonPath) {
        url = fileURL
    } else {
        url = URL(fileURLWithPath: jsonPath)
    }
    return url.resolvingSymlinksInPath().standardizedFileURL.path
}()

var status: Int32 = 0
/// Set when the screenshot has its answer (saved or not); the window can close before then, ending the
/// application, also while the PNG is being drawn (the completion then never runs).
var screenshotTried = false
MainActor.assumeIsolated {
    ActionUIModel.shared.trustPolicy = ViewerTrustPolicy(jsonPath: localJSONPath)
    let app = WinUIApplication.shared
    app.name = "ActionUI Viewer"
    // When the window is presented, which an http or https document makes later than the launch. The
    // handler runs before the document loads into the window: what follows waits for the next turn.
    app.handlers.windowWillPresent = { _ in
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                // A document that could not be loaded shows its error in the window; the run still fails.
                if !app.showsDocument(windowUUID) {
                    print("ActionUIViewer: \(jsonPath) could not be loaded")
                    status = 65
                }
                for (id, rows) in elementRows {
                    ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: id, rows: rows)
                }
                guard let screenshotPath else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + screenshotDelay) {
                    MainActor.assumeIsolated {
                        app.savePNG(windowUUID: windowUUID, path: screenshotPath) { saved in
                            screenshotTried = true
                            if saved {
                                print("ActionUIViewer: saved \(screenshotPath)")
                            } else {
                                print("ActionUIViewer: could not save \(screenshotPath)")
                                status = 1
                            }
                            app.terminate()
                        }
                    }
                }
            }
        }
    }
    app.presentWindow(url: jsonPath, windowUUID: windowUUID, title: nil)
    let ran = app.run()
    if let screenshotPath, !screenshotTried {
        print("ActionUIViewer: the window closed before \(screenshotPath) was saved")
        status = 1
    }
    if status == 0, !ran {
        status = 1
    }
}
exit(status)
