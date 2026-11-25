// Apps/ActionUIViewer/Sources/ActionUIViewerLinux/main.swift
/*
 ActionUIViewer: opens ActionUI JSON in a window on Linux, through AdwaitaApplication,
 with the add-ons that work on Linux (RichText, CachedImage, Diff, HostSurface). No client draws
 into a HostSurface here: it keeps its place in the layout and shows nothing.

 Usage: ActionUIViewer <file.json> [--dark] [--screenshot <file.png>] [--rows <id> <rows.json>]...

 The JSON is a path, a file URL, or an http or https URL (the window appears once it loads).
 - --dark: libadwaita's dark style, whatever the desktop's.
 - --screenshot: once the window has drawn, saves it as a PNG file (drawn by the window's own
   renderer, header bar included) and quits; the exit status says whether it was written.
 - ActionUI JSON that cannot be loaded shows its error in the window (saved too with --screenshot),
   and the exit status is 65.
 - --rows: sets the rows of the element with that id (a List, Table or Chart) from a JSON file
   holding an array of rows, each an array of strings, as a host's setElementRows does; for
   screenshots of data. A file that cannot be read or holds no such array stops the viewer (exit
   status 66).
 Actions the JSON fires have no handler here; they are logged.
*/

import CAdwaita
import Dispatch
import FoundationEssentials
import Glibc
import ActionUI
import ActionUIAdwaitaApplication
import ActionUICachedImage
import ActionUIDiff
import ActionUIRichText
import ActionUIHostSurface

let usage = "usage: ActionUIViewer <file.json> [--dark] [--screenshot <file.png>] [--rows <id> <rows.json>]..."
let windowUUID = "viewer"
/// How long the window has to draw before a screenshot is taken.
let screenshotDelay = DispatchTimeInterval.milliseconds(600)

var jsonPath: String?
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

/// The Viewer shows the JSON the user names, wherever it is: that local file is trusted (no
/// less than the bundle's would be), and so is a local file it names, though never above the
/// content around it, so a remote JSON file that names a local file keeps that file less trusted.
/// Remote ActionUI JSON keeps ActionUI's default, and a local file named where ActionUI cannot
/// tell the content around it stays less trusted: it gets a less-trusted parent, never none.
struct ViewerTrustPolicy: ActionUITrustPolicy {
    /// The resolved path of the local JSON file the user named, as JSONContentOrigin.Source.file
    /// gives it; nil for a remote JSON file.
    let jsonPath: String?

    func trust(for source: JSONContentOrigin.Source, inside parent: JSONContentOrigin?,
               byDefault: JSONContentOrigin.Trust) -> JSONContentOrigin.Trust {
        guard case .file(let path) = source else { return byDefault }
        if let parent { return parent.trust }
        return path == jsonPath ? .trusted : byDefault
    }
}

/// The named JSON file's path as presentWindow(url:) reads it: a file URL or a path; nil for an
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
/// Set when the screenshot was tried; the window can close before then, ending the application.
var screenshotTried = false
MainActor.assumeIsolated {
    ActionUIModel.shared.trustPolicy = ViewerTrustPolicy(jsonPath: localJSONPath)
    ActionUIRichText.register()
    ActionUICachedImage.register()
    ActionUIDiff.register()
    ActionUIHostSurface.register()
    let app = AdwaitaApplication.shared
    app.name = "ActionUI Viewer"
    app.applicationID = "com.abracode.actionui.viewer"
    app.handlers.willFinishLaunching = {
        if dark {
            adw_style_manager_set_color_scheme(adw_style_manager_get_default(), ADW_COLOR_SCHEME_FORCE_DARK)
        }
    }
    // When the window appears, which an http or https JSON file makes later than the launch.
    app.handlers.windowWillPresent = { _ in
        // ActionUI JSON that could not be loaded shows its error in the window; the run still fails.
        if !app.showsContent(windowUUID) {
            print("ActionUIViewer: \(jsonPath) could not be loaded")
            status = 65
        }
        for (id, rows) in elementRows {
            ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: id, rows: rows)
        }
        if let screenshotPath {
            DispatchQueue.main.asyncAfter(deadline: .now() + screenshotDelay) {
                screenshotTried = true
                if app.savePNG(windowUUID: windowUUID, path: screenshotPath) {
                    print("ActionUIViewer: saved \(screenshotPath)")
                } else {
                    print("ActionUIViewer: could not save \(screenshotPath)")
                    status = 1
                }
                app.terminate()
            }
        }
    }
    app.presentWindow(url: jsonPath, windowUUID: windowUUID, title: nil)
    let runStatus = app.run()
    if let screenshotPath, !screenshotTried {
        print("ActionUIViewer: the window closed before \(screenshotPath) was saved")
        status = 1
    }
    if status == 0 {
        status = runStatus
    }
}
exit(status)
