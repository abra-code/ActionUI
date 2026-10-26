// ActionUIAdwaita/Demo/main.swift
/*
 ActionUIDemo: the Linux counterpart of ActionUISwiftTestApp. A launcher window lists the app's
 documents (every .json file in its resources); choosing one opens it in a window of its own, as
 the Mac app's JSON Selector does. The documents are the test app's own
 (ActionUISwiftTestApp/Resources), shipped in a simplified iOS-style bundle with the program
 (Scripts/make-linux-demo-bundle.sh builds ActionUIDemo.app).

 Usage: ActionUIDemo [--resources <folder>] [--open <Name> [--action <actionID>]] [--dark] [--screenshot <file.png>]

 - --resources: the folder of the documents, when the program is not in its bundle (a development
   build); else the bundle (AppBundle).
 - --open: also opens the document Name (Name.json) at launch.
 - --action: fires the action on that document once it is shown, from the element whose actionID
   it is (0 when none), as clicking it would (for screenshots of what a handler does).
 - --screenshot: once the last window opened at launch has drawn (the --open one, else the
   launcher), saves it as a PNG file and quits.
 - Exit status: 64 for bad arguments, 66 when there are no documents or no document Name, 65 when
   the document opened with --open cannot be loaded (its window shows the error).
 The documents' actions run the test app's own handlers (ActionUISwiftTestApp/DemoHandlers.swift).
 The Mac app's menu commands (DefaultWindow.json's) are in each window's primary menu.
 What the Linux renderer does not do yet (alerts, sheets, navigation) shows in those documents.
*/

import CAdwaita
import Dispatch
import FoundationEssentials
import Glibc
import ActionUI
import ActionUISwiftAdapter

let usage = "usage: ActionUIDemo [--resources <folder>] [--open <Name> [--action <actionID>]] [--dark] [--screenshot <file.png>]"
// A name no document file gives (documents open under their names).
let launcherUUID = "actionui-demo-launcher"
let launcherListID = 1
let openActionID = "demo.open"
/// How long a window has to draw before a screenshot is taken.
let screenshotDelay = DispatchTimeInterval.milliseconds(600)

var resourcesArgument: String?
var openName: String?
var actionArgument: String?
var screenshotPath: String?
var dark = false
var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() {
    switch argument {
    case "--resources", "--open", "--action", "--screenshot":
        guard let value = arguments.popFirst() else {
            print(usage)
            exit(64)
        }
        switch argument {
        case "--resources": resourcesArgument = value
        case "--open": openName = value
        case "--action": actionArgument = value
        default: screenshotPath = value
        }
    case "--dark":
        dark = true
    default:
        print(usage)
        exit(64)
    }
}
if actionArgument != nil && openName == nil {
    print(usage)
    exit(64)
}

/// The launcher: a list of the documents, a click opening one.
let launcherDocument = """
    {"type": "List", "id": \(launcherListID), "properties": {"actionID": "\(openActionID)", "doubleClickActionID": "\(openActionID)",
     "frame": {"minWidth": 260, "idealWidth": 320, "minHeight": 360, "idealHeight": 640}}}
    """

/// The documents in `folder`, by name without ".json", sorted as the Mac app sorts them; as on the
/// Mac, DefaultWindow (the app's own window group) is left out, and so are hidden files.
func documentNames(in folder: String) -> [String] {
    let files = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
    return files.filter { name in
        var isFolder = false
        let path = URL(fileURLWithPath: folder).appendingPathComponent(name).path
        return name.hasSuffix(".json") && !name.hasPrefix(".") && name != "DefaultWindow.json"
            && FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) && !isFolder
    }
        .map { String($0.dropLast(".json".count)) }
        // Case-insensitive, as the Mac's localizedStandardCompare orders these names (no digits in them).
        .sorted { $0.lowercased() < $1.lowercased() }
}

var status: Int32 = 0
var screenshotTried = false
MainActor.assumeIsolated {
    let app = AdwaitaApplication.shared
    app.name = "ActionUI Demo"
    app.applicationID = "com.abracode.actionui.demo"
    if let resourcesArgument {
        app.resourceFolder = URL(fileURLWithPath: resourcesArgument).standardizedFileURL.path
    }
    guard let folder = app.resourceFolder else {
        print("ActionUIDemo: no documents: run it from ActionUIDemo.app, or give --resources <folder>")
        exit(66)
    }
    let names = documentNames(in: folder)
    guard !names.isEmpty else {
        print("ActionUIDemo: no .json documents in \(folder)")
        exit(66)
    }

    /// Opens the document `name` in its own window, or brings that window forward when it is open
    /// (a double click selects the row, which opens it, then activates it).
    @MainActor func open(_ name: String) {
        guard !app.showWindow(name) else { return }
        let path = URL(fileURLWithPath: folder).appendingPathComponent(name + ".json").path
        app.presentWindow(url: path, windowUUID: name, title: name)
    }

    // The Mac app's handlers; the modal sheet's document is in the resources too.
    DemoHandlers.register(resourceURL: { name, ext in
        URL(fileURLWithPath: folder).appendingPathComponent("\(name).\(ext)")
    })
    ActionUIModel.shared.registerActionHandler(for: openActionID) { _, windowUUID, viewID, _, _ in
        MainActor.assumeIsolated {
            guard let row = ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: viewID) as? [String],
                  let name = row.first, !name.isEmpty else { return }
            open(name)
        }
    }

    app.handlers.willFinishLaunching = {
        if dark {
            adw_style_manager_set_color_scheme(adw_style_manager_get_default(), ADW_COLOR_SCHEME_FORCE_DARK)
        }
    }
    let screenshotWindow = openName ?? launcherUUID
    app.handlers.windowWillPresent = { windowUUID in
        if windowUUID == launcherUUID {
            ActionUIModel.shared.setElementRows(windowUUID: launcherUUID, viewID: launcherListID, rows: names.map { [$0] })
        }
        // A document that could not be loaded shows its error in its window; the run fails.
        if windowUUID == openName, !app.showsDocument(windowUUID) {
            print("ActionUIDemo: \(windowUUID).json could not be loaded")
            status = 65
        }
        if windowUUID == openName, let actionArgument {
            // Once the window is on screen, from the element whose action it is, as a click on it would.
            DispatchQueue.main.async {
                let source = ActionUISwift.getElementInfo(windowUUID: windowUUID).keys.sorted().first { id in
                    ActionUISwift.getElementProperty(windowUUID: windowUUID, viewID: id, propertyName: "actionID") as? String == actionArgument
                }
                ActionUIModel.shared.actionHandler(actionArgument, windowUUID: windowUUID, viewID: source ?? 0, viewPartID: 0, context: nil)
            }
        }
        guard let screenshotPath, windowUUID == screenshotWindow else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + screenshotDelay) {
            screenshotTried = true
            if app.savePNG(windowUUID: windowUUID, path: screenshotPath) {
                print("ActionUIDemo: saved \(screenshotPath)")
            } else {
                print("ActionUIDemo: could not save \(screenshotPath)")
                status = 1
            }
            app.terminate()
        }
    }

    // The Mac app's menu commands (its DefaultWindow's), in each window's primary menu.
    let defaultWindow = URL(fileURLWithPath: folder).appendingPathComponent("DefaultWindow.json")
    if let data = try? Data(contentsOf: defaultWindow),
       let document = (try? ActionUIJSON.value(from: String(decoding: data, as: UTF8.self))) as? [String: Any],
       let commands = document["commands"],
       let json = try? ActionUIJSON.string(from: commands) {
        app.loadMenuBar(json: json)
    }

    app.presentWindow(json: Data(launcherDocument.utf8), windowUUID: launcherUUID, title: "ActionUI Demo")
    if let openName {
        guard names.contains(openName) else {
            print("ActionUIDemo: no document \(openName).json in \(folder)")
            exit(66)
        }
        open(openName)
    }
    let runStatus = app.run()
    if let screenshotPath, !screenshotTried {
        print("ActionUIDemo: the window closed before \(screenshotPath) was saved")
        status = 1
    }
    if status == 0 {
        status = runStatus
    }
}
exit(status)
