// ActionUIWinUI/Apps/Demo/Sources/ActionUIWinUIDemo/main.swift
/*
 ActionUIDemo: the Windows counterpart of ActionUISwiftTestApp, as ActionUIAdwaitaDemo is on Linux. A
 launcher window lists the app's JSON files (every .json file in its resources); choosing one opens it
 in a window of its own, as the Mac app's JSON Selector does. The JSON files are the test app's own
 (ActionUISwiftTestApp/Resources) and those of the add-ons that work on Windows.

 Usage: ActionUIWinUIDemo [--resources <folder>] [--open <Name> [--action <actionID>]] [--dark] [--screenshot <file.png>]

 - --resources: the folder of the JSON files; else the folder the program is in.
 - --open: also opens the JSON file Name (Name.json) at launch.
 - --action: fires the action on that JSON once it is shown, from the element whose actionID
   it is (0 when none), as clicking it would (for screenshots of what a handler does).
 - --screenshot: once the last window opened at launch has drawn (the --open one, else the
   launcher), saves what it shows below its title bar as a PNG file and quits.
 - --dark is accepted, as on Linux, and does nothing yet: the windows follow the system's theme.
 - Exit status: 64 for bad arguments, 66 when there are no JSON files or no JSON file Name, 65 when
   the JSON opened with --open cannot be loaded (its window shows the error).
 The JSON files' actions run the test app's own handlers (ActionUISwiftTestApp/DemoHandlers.swift).
 The add-ons that work on Windows (Diff, CachedImage, RichText, HostSurface) are linked and registered.
 The Mac app's menu commands (DefaultWindow.json's) are in each window's menu bar.
*/

import CWinUI
import Dispatch
import FoundationEssentials
import ucrt
import ActionUI
import ActionUICachedImage
import ActionUIDemoHandlers
import ActionUIDiff
import ActionUIHostSurface
import ActionUIRichText
import ActionUISwiftAdapter
import ActionUIWinUIApplication

// Before anything loads a DLL by name: a file named like one in the current folder is never loaded.
WinUIApplication.removeCurrentFolderFromDLLSearch()

let usage = "usage: ActionUIWinUIDemo [--resources <folder>] [--open <Name> [--action <actionID>]] [--dark] [--screenshot <file.png>]"
// A name no JSON file gives (JSON files open under their names).
let launcherUUID = "actionui-demo-launcher"
let launcherListID = 1
let openActionID = "demo.open"
/// How long a window has to draw before a screenshot is taken.
let screenshotDelay = DispatchTimeInterval.milliseconds(600)

var resourcesArgument: String?
var openName: String?
var actionArgument: String?
var screenshotPath: String?
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
        print("ActionUIDemo: --dark is not on Windows yet; the windows follow the system's theme")
    default:
        print(usage)
        exit(64)
    }
}
if actionArgument != nil && openName == nil {
    print(usage)
    exit(64)
}

/// The launcher: a list of the JSON files, a click opening one.
let launcherJSON = """
    {"type": "List", "id": \(launcherListID), "properties": {"actionID": "\(openActionID)", "doubleClickActionID": "\(openActionID)",
     "frame": {"minWidth": 260, "idealWidth": 320, "minHeight": 360, "idealHeight": 640}}}
    """

/// The folder of the running program; nil only when Windows cannot tell it.
func programFolder() -> String? {
    guard let copy = actionUIWinUICopyProgramFolder() else { return nil }
    defer { actionUIWinUIFreeString(copy) }
    return String(cString: copy)
}

/// The JSON files in `folder`, by name without ".json", sorted as the Mac app sorts them; as on the
/// Mac, DefaultWindow (the app's own window group) is left out, and so are hidden files.
func jsonNames(in folder: String) -> [String] {
    let files = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
    return files.filter { name in
        var isFolder = false
        let path = URL(fileURLWithPath: folder).appendingPathComponent(name).path
        return name.lowercased().hasSuffix(".json") && !name.hasPrefix(".") && name != "DefaultWindow.json"
            && FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) && !isFolder
    }
        .map { String($0.dropLast(".json".count)) }
        // Case-insensitive, as the Mac's localizedStandardCompare orders these names (no digits in them).
        .sorted { $0.lowercased() < $1.lowercased() }
}

var status: Int32 = 0
/// Set when the screenshot has its answer (saved or not); the window can close before then, ending the
/// application, also while the PNG is being drawn (the completion then never runs).
var screenshotTried = false
MainActor.assumeIsolated {
    ActionUIRichText.register()
    ActionUICachedImage.register()
    ActionUIDiff.register()
    ActionUIHostSurface.register()
    let app = WinUIApplication.shared
    app.name = "ActionUI Demo"
    guard let folder = resourcesArgument.map({ URL(fileURLWithPath: $0).standardizedFileURL.path }) ?? programFolder() else {
        print("ActionUIDemo: no JSON files: Windows did not tell the program's folder; give --resources <folder>")
        exit(66)
    }
    app.resourceFolder = folder
    let names = jsonNames(in: folder)
    guard !names.isEmpty else {
        print("ActionUIDemo: no .json files in \(folder)")
        exit(66)
    }

    /// Opens the JSON file `name` in its own window, or brings that window forward when it is open
    /// (a double click selects the row, which opens it, then activates it).
    @MainActor func open(_ name: String) {
        guard !app.showWindow(name) else { return }
        let path = URL(fileURLWithPath: folder).appendingPathComponent(name + ".json").path
        app.presentWindow(url: path, windowUUID: name, title: name)
    }

    // The Mac app's handlers; the modal sheet's JSON is in the resources too.
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

    let screenshotWindow = openName ?? launcherUUID
    /// The window showing `windowUUID` has loaded its JSON.
    @MainActor func shown(_ windowUUID: String) {
        if windowUUID == launcherUUID {
            ActionUIModel.shared.setElementRows(windowUUID: launcherUUID, viewID: launcherListID, rows: names.map { [$0] })
        }
        // The Diff JSON's second element (id 81) diffs two bundled text files by absolute path, set
        // as the add-ons' test app does on Apple.
        if windowUUID == "Diff" {
            for (property, file) in [("oldFile", "DiffSampleOld.txt"), ("newFile", "DiffSampleNew.txt")] {
                let path = URL(fileURLWithPath: folder).appendingPathComponent(file).path
                ActionUISwift.setElementProperty(windowUUID: windowUUID, viewID: 81, propertyName: property, value: path)
            }
        }
        // ActionUI JSON that could not be loaded shows its error in its window; the run fails.
        if windowUUID == openName, !app.showsContent(windowUUID) {
            print("ActionUIDemo: \(windowUUID).json could not be loaded")
            status = 65
        }
        if windowUUID == openName, let actionArgument {
            // From the element whose action it is, as a click on it would.
            let source = ActionUISwift.getElementInfo(windowUUID: windowUUID).keys.sorted().first { id in
                ActionUISwift.getElementProperty(windowUUID: windowUUID, viewID: id, propertyName: "actionID") as? String == actionArgument
            }
            ActionUIModel.shared.actionHandler(actionArgument, windowUUID: windowUUID, viewID: source ?? 0, viewPartID: 0, context: nil)
        }
        guard let screenshotPath, windowUUID == screenshotWindow else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + screenshotDelay) {
            MainActor.assumeIsolated {
                app.savePNG(windowUUID: windowUUID, path: screenshotPath) { saved in
                    screenshotTried = true
                    if saved {
                        print("ActionUIDemo: saved \(screenshotPath)")
                    } else {
                        print("ActionUIDemo: could not save \(screenshotPath)")
                        status = 1
                    }
                    app.terminate()
                }
            }
        }
    }

    // The handler runs before the JSON loads into the window: what follows waits for the next turn.
    app.handlers.windowWillPresent = { windowUUID in
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                shown(windowUUID)
            }
        }
    }

    // The Mac app's menu commands (its DefaultWindow's), in each window's menu bar.
    let defaultWindow = URL(fileURLWithPath: folder).appendingPathComponent("DefaultWindow.json")
    if let data = FileManager.default.contents(atPath: defaultWindow.path),
       let parsed = (try? ActionUIJSON.value(from: String(decoding: data, as: UTF8.self))) as? [String: Any],
       let commands = parsed["commands"],
       let json = try? ActionUIJSON.string(from: commands) {
        app.loadMenuBar(json: json)
    }

    app.presentWindow(json: launcherJSON, windowUUID: launcherUUID, title: "ActionUI Demo")
    if let openName {
        guard names.contains(openName) else {
            print("ActionUIDemo: no JSON file \(openName).json in \(folder)")
            exit(66)
        }
        open(openName)
    }
    let ran = app.run()
    if let screenshotPath, !screenshotTried {
        print("ActionUIDemo: the window closed before \(screenshotPath) was saved")
        status = 1
    }
    if status == 0, !ran {
        status = 1
    }
}
exit(status)
