// ActionUIWinUI/Apps/Preview/main.swift - ActionUIWinUIPreview: renders an ActionUI document with
// the WinUI renderer into a PNG of the window's whole content area (below the title bar), in a
// window of the given content size, and prints where WinUI placed each element (its frame in its
// parent), so a run can be compared with SwiftUI's and GTK's.
//
// Usage: ActionUIWinUIPreview DOCUMENT.json PNG_PATH [WIDTH HEIGHT] [options]
//   Relative image paths in the document are taken from the document's folder.
//   --invoke ID              after the first layout, operates element ID as an accessibility tool
//                            does (UI Automation's Invoke: a Button is pressed); repeatable, in order
//   --toggle ID              the same with UI Automation's Toggle (a Toggle turns over)
//   --invoke-row ID ROW      the same with the element List ID shows in row ROW (from 0; a Button cell)
//   --invoke-part ID N       the same with the Nth part (from 0) of element ID that can be invoked (a
//                            Stepper's minus is 0, its plus 1)
//   --select-part ID N       the same with UI Automation's SelectionItem and the Nth part (from 0) of
//                            element ID that can be selected (a TabView's tab, a List's row)
//   --set-text ID TEXT       the same with UI Automation's SetValue (a TextField's text, as typed; a
//                            Slider's position, TEXT read as a number; a ColorPicker's color, TEXT
//                            "#RRGGBB" or "#RRGGBBAA", as picked in its flyout)
//   --scroll ID X Y          scrolls ScrollView ID to the offset (X, Y), without animation
//   --scroll-row ID ROW      scrolls List ID so that row ROW (from 0) is in view
//   --expect-row-name ID ROW NAME  fails unless accessibility tools name List ID's row ROW (from 0) NAME
//   --drag ID X1 Y1 X2 Y2    drags with the real mouse from (X1, Y1) to (X2, Y2) in element ID's
//                            coordinates, as a user does (it moves the pointer of whoever runs it)
//   --wheel ID X Y DX DY     turns the real mouse wheel over (X, Y) in element ID's coordinates, DY
//                            notches toward the bottom (a wheel turned toward the user) and the tilt
//                            wheel DX notches toward the right, as a user does (it moves the pointer)
//   --expect-width ID W      fails unless element ID (its frame in its parent) is W wide, within half a
//                            point (a split view's pane after a drag)
//   --invoke-menu-item ID N  the same as --invoke with the Nth item (from 0) of Menu ID's menu (separators
//                            and headers count), as a click on it does
//   --toggle-menu-item ID N  the same with UI Automation's Toggle (a Toggle's check item turns over)
//   --add-row ID TEXT        appends a row to element ID's content through the model, as an adapter
//                            does (a List's rows), its columns TEXT split at "|"; repeatable, in order.
//                            An operation on an element after rows or properties changed waits for
//                            the change to reach the screen (a template row's controls are made then)
//   --add-rows ID N TEXT     appends N rows at once, as --add-row, each TEXT with "#" replaced by the
//                            row's number from 1 (a long lazy stack)
//   --set-value ID VALUE     sets element ID's value through the model, as an adapter does (VALUE a
//                            number when it reads as one, else a string)
//   --set-property ID NAME VALUE  sets element ID's property NAME through the model, as an adapter
//                            does (VALUE an Int when it reads as a whole number, else a number when
//                            it reads as one, else a string)
//   --set-path ID IDS        sets NavigationStack ID's navigationPath state through the model, as an
//                            adapter does (IDS the destination ids, comma separated; "-" for none)
//   --set-state ID KEY VALUE sets element ID's state KEY through the model, as an adapter does
//                            (VALUE "true" or "false" a Bool, a number a Double, else the text):
//                            sheetVisible false closes a sheet
//   --expect-state ID KEY VALUE  fails unless element ID's state KEY reads VALUE (as text: "true",
//                            "0.5", a string) at that point (a WebView's title after a --delay)
//   --expect-automation ID FIELD TEXT  fails unless an accessibility tool reads TEXT as element ID's
//                            FIELD ("name", "help", "id" or "accelerator", its keyboard shortcut),
//                            through its UI Automation peer
//   --delay MS               waits MS milliseconds before the next operation (or the rendering): a
//                            LoadableView's remote description loading
//   --wait                   lets the changes the operations before it made reach the screen before
//                            the next operation on screen (a screen pushed by an invoke, then its
//                            back button)
//   --max-instances ID N     fails when element ID holds more than N template instances when the
//                            window is rendered (a lazy stack made rows out of view)
//   --expect-action ACTION   fails unless the action ACTION fired; repeatable
//   --forbid-action ACTION   fails if the action ACTION fired (a renderer's own change taken for the
//                            user's); repeatable. Actions after the rendering, as the window closes,
//                            count for neither
//   --expect-log TEXT        fails unless a message ActionUI logged contains TEXT (a VideoPlayer's
//                            video opened); repeatable
//   --on-action ACTION ID TEXT  when ACTION fires, sets element ID's value to TEXT (a Text shows it)
//   --fetch-limit BYTES      a LoadableView's download is refused past BYTES (default: 16 MB)
//   --configuration JSON     the host's configuration (ActionUIConfiguration), before the document loads
//   --refuse-remote-loads    a host trust policy that refuses LoadableViews' remote loads
//   --no-launch              a Link the trust policy lets open logs its address and opens nothing (no
//                            browser or other app starts)
// Every action that fires is printed. Prints "preview:" lines; exit status 0 when the document
// loaded and rendered, the PNG is not empty, every operation worked, every expected action fired
// at least once, every expected log message was logged and no element held more template instances
// than --max-instances allows. Built and
// run by
// Scripts/ci-windows.py winui.

import ActionUI
import CWinUI
import Dispatch
import ucrt
import Synchronization

@MainActor
final class Preview {
    static let shared = Preview()

    var documentPath = ""
    var pngPath = ""
    var contentSize = ActionUIWinUISize(width: 480, height: 320)
    var window: WinUIObject?
    var tree: WinUIWindow?
    var rendered = false
    /// The --invoke, --toggle, --set-text, --scroll and --set-property operations, in order.
    var invocations: [Operation] = []

    enum Operation {
        case invoke(Int), invokeRow(Int, Int), invokePart(Int, Int), selectPart(Int, Int), toggle(Int), setText(Int, String), scroll(Int, Double, Double), scrollRow(Int, Int), expectRowName(Int, Int, String), invokeMenuItem(Int, Int), toggleMenuItem(Int, Int),
             drag(Int, Double, Double, Double, Double), wheel(Int, Double, Double, Double, Double), expectWidth(Int, Double), delay(Int), expectState(Int, String, String), expectAutomation(Int, String, String),
             setProperty(Int, String, String), setValue(Int, String), addRow(Int, String), addRows(Int, Int, String), setPath(Int, [Int]), setState(Int, String, String), wait

        var viewID: Int {
            switch self {
            case .invoke(let id), .invokeRow(let id, _), .invokePart(let id, _), .selectPart(let id, _), .toggle(let id), .setText(let id, _), .scroll(let id, _, _), .scrollRow(let id, _), .expectRowName(let id, _, _), .invokeMenuItem(let id, _), .toggleMenuItem(let id, _), .setProperty(let id, _, _), .setValue(let id, _),
                 .drag(let id, _, _, _, _), .wheel(let id, _, _, _, _), .expectWidth(let id, _), .expectState(let id, _, _), .expectAutomation(let id, _, _),
                 .addRow(let id, _), .addRows(let id, _, _), .setPath(let id, _), .setState(let id, _, _):
                return id
            case .wait, .delay:
                return 0
            }
        }

        /// Whether what it changes reaches the screen later (the model's changes after a sync, a drag's
        /// input as the UI thread takes it), so an operation on screen after it waits.
        var showsLater: Bool {
            switch self {
            case .setProperty, .setValue, .addRow, .addRows, .setPath, .setState, .wait, .drag, .wheel, .delay: true
            case .invoke, .invokeRow, .invokePart, .selectPart, .toggle, .setText, .scroll, .scrollRow, .expectRowName, .invokeMenuItem, .toggleMenuItem, .expectWidth, .expectState, .expectAutomation: false
            }
        }

        /// Whether it operates an element on screen, so it waits for an earlier change to be shown. A
        /// drag does both: it reads where the element is now, and its input reaches the screen later.
        var operatesOnScreen: Bool {
            switch self {
            case .drag, .wheel:
                return true
            default:
                break
            }
            return !showsLater
        }
    }
    var expectedActions: [String] = []
    var forbiddenActions: [String] = []
    var valuesOnAction: [String: (viewID: Int, text: String)] = [:]
    var firedActions: [String] = []
    /// False once an --invoke found no element or the shim refused it.
    var invocationsWorked = true
    /// --max-instances: element id to the most template instances it may hold.
    var maxInstances: [Int: Int] = [:]
    /// False once an element held more template instances than --max-instances allows.
    var instancesWithinLimit = true

    func say(_ line: String) {
        print("preview: \(line)")
    }

    func launched() {
        guard MainLoopBridge.install() else {
            say("the main queue bridge could not be installed")
            finish()
            return
        }
        guard let json = readFile(documentPath) else {
            say("cannot read \(documentPath)")
            finish()
            return
        }
        // Relative image paths in the document are taken from its folder (the PNG path was made
        // absolute before).
        if let folder = documentFolder(documentPath) {
            let changed = folder.withCString(encodedAs: UTF16.self) { _wchdir($0) }
            if changed != 0 {
                say("cannot change to the document's folder \(folder)")
            }
        }
        do {
            let tree = try WinUIWindow.load(json: json, windowUUID: "preview")
            self.tree = tree
            // No view: no element loaded, no view model for the root, or its WinUI object could not
            // be made (the log says which).
            guard let content = tree.view else {
                say("the document has no root element to show")
                finish()
                return
            }
            guard let window = WinUIObject(adopting: actionUIWinUIWindowCreate()) else {
                say(WinUIError.last("creating the window").description)
                finish()
                return
            }
            self.window = window
            guard actionUIWinUIWindowSetTitle(window.pointer, "ActionUI WinUI preview"),
                  actionUIWinUIWindowSetContentSize(window.pointer, contentSize.width, contentSize.height),
                  actionUIWinUIWindowSetContent(window.pointer, content.pointer),
                  actionUIWinUIWindowActivate(window.pointer) else {
                say(WinUIError.last("setting up the window").description)
                finish()
                return
            }
        } catch {
            say("the document did not load: \(error)")
            finish()
            return
        }
        ActionUIModel.shared.setDefaultActionHandler { actionID, windowUUID, viewID, _, context in
            let shownContext = context.map { "\($0)" }
            MainActor.assumeIsolated {
                Preview.shared.actionFired(actionID, windowUUID: windowUUID, viewID: viewID, context: shownContext)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(800)) {
            MainActor.assumeIsolated { Preview.shared.invokeThenRender() }
        }
    }

    func actionFired(_ actionID: String, windowUUID: String, viewID: Int, context: String?) {
        // After the rendering the window closes: what fires then (an onDisappear) is the closing's,
        // printed but not counted for --expect-action and --forbid-action.
        guard !rendered else {
            say("action \(actionID) from element \(viewID) as the window closes (not counted)")
            return
        }
        firedActions.append(actionID)
        say("action \(actionID) from element \(viewID)" + (context.map { " with context \($0)" } ?? ""))
        if let change = valuesOnAction[actionID] {
            ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: change.viewID, value: change.text)
        }
    }

    /// Operates the elements named by --invoke, then lets the model's changes reach WinUI (a sync,
    /// then a layout) before reporting and rendering.
    func invokeThenRender() {
        guard !invocations.isEmpty else {
            reportAndRender()
            return
        }
        runOperations(from: 0)
    }

    /// Runs the operations from `start` on, in order. One that operates an element on screen after
    /// one whose change reaches the screen later waits for it to be shown first.
    func runOperations(from start: Int) {
        for position in start..<invocations.count {
            let operation = invocations[position]
            if position > start, operation.operatesOnScreen, invocations[position - 1].showsLater {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300)) {
                    MainActor.assumeIsolated { Preview.shared.runOperations(from: position) }
                }
                return
            }
            if case .wait = operation {
                say("waiting for the changes to be shown")
                continue
            }
            if case .delay(let milliseconds) = operation {
                say("waiting \(milliseconds) ms")
                let next = position + 1
                // Last: the rendering after the usual settling time too.
                let settle = next < invocations.count ? 0 : 500
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds + settle)) {
                    MainActor.assumeIsolated {
                        if next < Preview.shared.invocations.count {
                            Preview.shared.runOperations(from: next)
                        } else {
                            Preview.shared.reportAndRender()
                        }
                    }
                }
                return
            }
            let viewID = operation.viewID
            guard let node = tree?.root.flatMap({ find(viewID, in: $0) }), let view = node.view else {
                say("element \(viewID): no such element on screen")
                invocationsWorked = false
                continue
            }
            let worked: Bool
            let what: String
            switch operation {
            case .invoke:
                worked = actionUIWinUIAutomationInvoke(view.pointer)
                what = "invoked"
            case .invokeRow(_, let row):
                if let element = WinUIObject(adopting: actionUIWinUIListCopyItemElement(view.pointer, Int32(row))) {
                    worked = actionUIWinUIAutomationInvoke(element.pointer)
                } else {
                    worked = false
                }
                what = "invoked row \(row) of"
            case .invokePart(_, let part):
                worked = actionUIWinUIAutomationInvokePart(view.pointer, Int32(part))
                what = "invoked part \(part) of"
            case .selectPart(_, let part):
                worked = actionUIWinUIAutomationSelectPart(view.pointer, Int32(part))
                what = "selected part \(part) of"
            case .toggle:
                worked = actionUIWinUIAutomationToggle(view.pointer)
                what = "toggled"
            case .setText(_, let text):
                worked = actionUIWinUIAutomationSetValue(view.pointer, text)
                what = "set the text of"
            case .scroll(_, let x, let y):
                worked = actionUIWinUIScrollViewerScrollTo(view.pointer, x, y)
                what = "scrolled"
            case .scrollRow(_, let row):
                worked = actionUIWinUIListScrollIntoView(view.pointer, Int32(row))
                what = "scrolled to row \(row) of"
            case .expectRowName(_, let row, let expected):
                guard let copy = actionUIWinUIListCopyRowName(view.pointer, Int32(row)) else {
                    worked = false
                    what = "reading the name of row \(row) of"
                    break
                }
                let name = String(cString: copy)
                actionUIWinUIFreeString(copy)
                // A wrong name is reported here: the shim has no error for it.
                guard name == expected else {
                    say("element \(viewID): row \(row) is named \"\(name)\", not \"\(expected)\"")
                    invocationsWorked = false
                    continue
                }
                worked = true
                what = "found row \(row) named \"\(name)\" in"
            case .expectState(_, let key, let expected):
                let shown = node.model.states[key].map { "\($0)" } ?? "(none)"
                // A wrong state is reported here: the shim has no error for it.
                guard shown == expected else {
                    say("element \(viewID): state \(key) is \"\(shown)\", not \"\(expected)\"")
                    invocationsWorked = false
                    continue
                }
                worked = true
                what = "found state \(key) \"\(shown)\" in"
            case .expectAutomation(_, let field, let expected):
                let which: ActionUIWinUIAutomationText
                switch field {
                case "name": which = ActionUIWinUIAutomationName
                case "help": which = ActionUIWinUIAutomationHelpText
                case "accelerator": which = ActionUIWinUIAutomationAcceleratorKey
                default: which = ActionUIWinUIAutomationIdentifier
                }
                guard let copy = actionUIWinUIElementCopyAutomationText((node.accessibleView ?? view).pointer, which) else {
                    say("element \(viewID): \(WinUIError.last("reading its \(field)"))")
                    invocationsWorked = false
                    continue
                }
                let shown = String(cString: copy)
                actionUIWinUIFreeString(copy)
                guard shown == expected else {
                    say("element \(viewID): accessibility \(field) is \"\(shown)\", not \"\(expected)\"")
                    invocationsWorked = false
                    continue
                }
                worked = true
                what = "found accessibility \(field) \"\(shown)\" in"
            case .drag(_, let fromX, let fromY, let toX, let toY):
                worked = window.map { actionUIWinUIWindowSendDrag($0.pointer, view.pointer, fromX, fromY, toX, toY) } ?? false
                what = "dragged from (\(fromX), \(fromY)) to (\(toX), \(toY)) in"
            case .wheel(_, let x, let y, let notchesX, let notchesY):
                worked = window.map { actionUIWinUIWindowSendWheel($0.pointer, view.pointer, x, y, notchesX, notchesY) } ?? false
                what = "turned the wheel (\(notchesX), \(notchesY)) notches at (\(x), \(y)) in"
            case .expectWidth(_, let expected):
                let width = node.outerView?.layoutFrame.width ?? 0
                // A wrong width is reported here: the shim has no error for it.
                guard abs(width - expected) <= 0.5 else {
                    say("element \(viewID): \(width) wide, not \(expected)")
                    invocationsWorked = false
                    continue
                }
                worked = true
                what = "found \(width) wide"
            case .invokeMenuItem(_, let index), .toggleMenuItem(_, let index):
                let toggles: Bool
                if case .toggleMenuItem = operation { toggles = true } else { toggles = false }
                if let menu = WinUIObject(adopting: actionUIWinUIMenuButtonCopyMenu(view.pointer)),
                   let item = WinUIObject(adopting: actionUIWinUIMenuCopyItem(menu.pointer, Int32(index))) {
                    worked = toggles ? actionUIWinUIAutomationToggle(item.pointer) : actionUIWinUIAutomationInvoke(item.pointer)
                } else {
                    worked = false
                }
                what = "\(toggles ? "toggled" : "invoked") menu item \(index) of"
            case .setProperty(_, let name, let text):
                // A whole number as an Int, as a host's JSON gives it (scrollTo is read as an Int).
                let value: Any
                if let integer = Int(text) {
                    value = integer
                } else if let number = Double(text) {
                    value = number
                } else {
                    value = text
                }
                ActionUIModel.shared.setElementProperty(windowUUID: "preview", viewID: viewID, propertyName: name, value: value)
                worked = true
                what = "set \(name) to \(text) on"
            case .setValue(_, let text):
                let value: Any = Double(text) ?? text
                ActionUIModel.shared.setElementValue(windowUUID: "preview", viewID: viewID, value: value)
                worked = true
                what = "set the value to \(text) of"
            case .setPath(_, let ids):
                worked = ActionUIModel.shared.setElementState(windowUUID: "preview", viewID: viewID, key: "navigationPath", value: ids)
                what = "set the path to \(ids) of"
            case .setState(_, let key, let text):
                let value: Any = text == "true" ? true : text == "false" ? false : (Double(text).map { $0 as Any } ?? text)
                worked = ActionUIModel.shared.setElementState(windowUUID: "preview", viewID: viewID, key: key, value: value)
                what = "set the state \(key) to \(text) of"
            case .wait, .delay:
                continue
            case .addRow(_, let text):
                let columns = text.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                ActionUIModel.shared.appendElementRows(windowUUID: "preview", viewID: viewID, rows: [columns])
                worked = true
                what = "added the row \(text) to"
            case .addRows(_, let count, let text):
                let rows = (1...max(count, 1)).map { number in
                    text.split(separator: "#", omittingEmptySubsequences: false).joined(separator: String(number))
                        .split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                }
                ActionUIModel.shared.appendElementRows(windowUUID: "preview", viewID: viewID, rows: count > 0 ? rows : [])
                worked = true
                what = "added \(count) rows (\(text)) to"
            }
            if worked {
                say("\(what) \(node.element.type) \(viewID)")
            } else {
                say("element \(viewID): \(WinUIError.last(what))")
                invocationsWorked = false
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
            MainActor.assumeIsolated { Preview.shared.reportAndRender() }
        }
    }

    /// The node of element `viewID` in the tree under `node`.
    func find(_ viewID: Int, in node: RenderNode) -> RenderNode? {
        if node.element.id == viewID {
            return node
        }
        // A template's ids repeat in every row: the instance made first (the first row's until a row is
        // replaced).
        // A sheet's or popover's tree too, while it is shown.
        for child in node.orderedChildren + node.templateNodes + node.auxiliaryNodes + (node.presentations?.roots ?? []) {
            if let found = find(viewID, in: child) {
                return found
            }
        }
        return nil
    }

    func reportAndRender() {
        if let root = tree?.root {
            report(root, indent: "")
        }
        guard let window else {
            finish()
            return
        }
        // The whole content area, as the window shows it below its title bar.
        let started = actionUIWinUIWindowRenderToPNG(window.pointer, pngPath, { _, succeeded in
            MainActor.assumeIsolated { Preview.shared.renderDone(succeeded) }
        }, nil)
        if !started {
            say(WinUIError.last("starting the render").description)
            finish()
        }
    }

    /// Prints the node's element and frame, then its children's, in document order.
    func report(_ node: RenderNode, indent: String) {
        // The box's frame in its parent: the element with its padding and frame, as SwiftUI reports one.
        let frame = node.outerView?.layoutFrame ?? ActionUIWinUIRect(x: 0, y: 0, width: 0, height: 0)
        say("\(indent)\(node.element.type) \(node.element.id): (\(frame.x), \(frame.y), \(frame.width), \(frame.height))"
            + (node.templateNodes.isEmpty ? "" : ", \(node.templateNodes.count) template instances"))
        if let limit = maxInstances[node.element.id], node.templateNodes.count > limit {
            say("element \(node.element.id) holds \(node.templateNodes.count) template instances, more than \(limit)")
            instancesWithinLimit = false
        }
        for child in node.orderedChildren + node.templateNodes + node.auxiliaryNodes {
            report(child, indent: indent + "  ")
        }
        // A shown sheet's or popover's tree, its frames in its own content.
        for root in node.presentations?.roots ?? [] {
            say("\(indent)  presented:")
            report(root, indent: indent + "    ")
        }
    }

    func renderDone(_ succeeded: Bool) {
        rendered = succeeded
        say(succeeded ? "rendered \(pngPath)" : WinUIError.last("rendering").description)
        finish()
    }

    /// Closes the window and lets go of every object, then quits; on the UI thread, before
    /// actionUIWinUIRun returns.
    func finish() {
        if let window {
            _ = actionUIWinUIWindowClose(window.pointer)
        }
        tree?.detach()
        tree = nil
        window = nil
        actionUIWinUIQuit()
    }
}

/// `path` made absolute against the current folder (the C runtime's _wfullpath), or `path` itself when
/// that fails.
func absolutePath(_ path: String) -> String {
    let full = path.withCString(encodedAs: UTF16.self) { _wfullpath(nil, $0, 0) }
    guard let full else { return path }
    defer { free(full) }
    return String(decodingCString: full, as: UTF16.self)
}

/// The folder holding the file at `path` (its absolute form), or nil when it has none.
func documentFolder(_ path: String) -> String? {
    let absolute = absolutePath(path)
    guard let slash = absolute.lastIndex(where: { $0 == "\\" || $0 == "/" }) else { return nil }
    let folder = String(absolute[..<slash])
    // A drive's root keeps its backslash: "C:" alone is the current folder on drive C.
    return folder.hasSuffix(":") ? folder + "\\" : folder
}

/// The UTF-8 text of the file at `path`, or nil. Through the C runtime's wide calls: its narrow ones
/// read a path in the ANSI code page.
func readFile(_ path: String) -> String? {
    var opened: UnsafeMutablePointer<FILE>?
    let status = path.withCString(encodedAs: UTF16.self) { widePath in
        "rb".withCString(encodedAs: UTF16.self) { wideMode in
            _wfopen_s(&opened, widePath, wideMode)
        }
    }
    guard status == 0, let file = opened else {
        return nil
    }
    defer { fclose(file) }
    var bytes: [UInt8] = []
    var chunk = [UInt8](repeating: 0, count: 65536)
    while true {
        let count = fread(&chunk, 1, chunk.count, file)
        if count == 0 {
            break
        }
        bytes.append(contentsOf: chunk[0..<count])
    }
    return String(decoding: bytes, as: UTF8.self)
}

/// The size of the file at `path`, or -1.
func fileSize(_ path: String) -> Int {
    var opened: UnsafeMutablePointer<FILE>?
    let status = path.withCString(encodedAs: UTF16.self) { widePath in
        "rb".withCString(encodedAs: UTF16.self) { wideMode in
            _wfopen_s(&opened, widePath, wideMode)
        }
    }
    guard status == 0, let file = opened else {
        return -1
    }
    defer { fclose(file) }
    guard fseek(file, 0, SEEK_END) == 0 else {
        return -1
    }
    return Int(ftell(file))
}

setvbuf(__acrt_iob_func(1), nil, _IONBF, 0)  // stdout, unbuffered: the lines must survive a crash

let arguments = CommandLine.arguments
/// The destination ids of --set-path's IDS ("-": none), or nil when one is not a number.
func pathIDs(_ text: String) -> [Int]? {
    guard text != "-" else { return [] }
    let ids = text.split(separator: ",").compactMap { Int($0) }
    return ids.count == text.split(separator: ",", omittingEmptySubsequences: false).count ? ids : nil
}

/// --refuse-remote-loads: ActionUI's default policy, except that no LoadableView loads from a server.
struct RefusingRemoteLoads: ActionUITrustPolicy {
    @MainActor func allows(_ capability: ActionUICapability, for origin: JSONContentOrigin) -> Bool {
        if case .load(.remote) = capability {
            return false
        }
        return DefaultTrustPolicy.allowsByDefault(capability, for: origin)
    }
}

/// A logger that keeps every message (for --expect-log) and passes it on.
final class RecordingLogger: ActionUILogger {
    private let inner: any ActionUILogger
    private let recorded = Mutex<[String]>([])

    init(forwardingTo inner: any ActionUILogger) {
        self.inner = inner
    }

    var messages: [String] { recorded.withLock { $0 } }

    func log(_ message: String, _ level: LoggerLevel) {
        recorded.withLock { $0.append(message) }
        inner.log(message, level)
    }
}

let usage = "usage: ActionUIWinUIPreview DOCUMENT.json PNG_PATH [WIDTH HEIGHT] [--invoke ID | --invoke-row ID ROW | --invoke-part ID N | --select-part ID N | --toggle ID | --set-text ID TEXT | --scroll ID X Y | --scroll-row ID ROW | --expect-row-name ID ROW NAME | --drag ID X1 Y1 X2 Y2 | --wheel ID X Y DX DY | --expect-width ID W | --invoke-menu-item ID N | --toggle-menu-item ID N | --set-value ID VALUE | --set-property ID NAME VALUE | --set-path ID IDS | --add-row ID TEXT | --add-rows ID N TEXT | --set-state ID KEY VALUE | --expect-state ID KEY VALUE | --expect-automation ID FIELD TEXT | --delay MS | --wait]... [--max-instances ID N]... [--expect-action ACTION]... [--expect-log TEXT]... [--forbid-action ACTION]... [--on-action ACTION ID TEXT]... [--no-launch] [--fetch-limit BYTES] [--refuse-remote-loads] [--configuration JSON]"
guard arguments.count >= 3 else {
    print(usage)
    exit(64)
}
let preview = Preview.shared
/// --expect-log: the texts some logged message must contain.
var expectedLogs: [String] = []
preview.documentPath = arguments[1]
// Absolute, since the program changes to the document's folder once it has read it.
preview.pngPath = absolutePath(arguments[2])
var index = 3
if arguments.count >= 5, let width = Double(arguments[3]), let height = Double(arguments[4]) {
    guard width > 0, height > 0 else {
        print("preview: WIDTH and HEIGHT must be positive")
        exit(64)
    }
    preview.contentSize = ActionUIWinUISize(width: width, height: height)
    index = 5
}
while index < arguments.count {
    let option = arguments[index]
    if option == "--invoke", index + 1 < arguments.count, let viewID = Int(arguments[index + 1]) {
        preview.invocations.append(.invoke(viewID))
        index += 2
    } else if option == "--invoke-row", index + 2 < arguments.count, let viewID = Int(arguments[index + 1]),
              let row = Int(arguments[index + 2]) {
        preview.invocations.append(.invokeRow(viewID, row))
        index += 3
    } else if option == "--invoke-part", index + 2 < arguments.count, let viewID = Int(arguments[index + 1]),
              let part = Int(arguments[index + 2]) {
        preview.invocations.append(.invokePart(viewID, part))
        index += 3
    } else if option == "--select-part", index + 2 < arguments.count, let viewID = Int(arguments[index + 1]),
              let part = Int(arguments[index + 2]) {
        preview.invocations.append(.selectPart(viewID, part))
        index += 3
    } else if option == "--toggle", index + 1 < arguments.count, let viewID = Int(arguments[index + 1]) {
        preview.invocations.append(.toggle(viewID))
        index += 2
    } else if option == "--set-text", index + 2 < arguments.count, let viewID = Int(arguments[index + 1]) {
        preview.invocations.append(.setText(viewID, arguments[index + 2]))
        index += 3
    } else if option == "--scroll", index + 3 < arguments.count, let viewID = Int(arguments[index + 1]),
              let x = Double(arguments[index + 2]), let y = Double(arguments[index + 3]) {
        preview.invocations.append(.scroll(viewID, x, y))
        index += 4
    } else if option == "--scroll-row", index + 2 < arguments.count, let viewID = Int(arguments[index + 1]),
              let row = Int(arguments[index + 2]) {
        preview.invocations.append(.scrollRow(viewID, row))
        index += 3
    } else if option == "--expect-row-name", index + 3 < arguments.count, let viewID = Int(arguments[index + 1]),
              let row = Int(arguments[index + 2]) {
        preview.invocations.append(.expectRowName(viewID, row, arguments[index + 3]))
        index += 4
    } else if option == "--drag", index + 5 < arguments.count, let viewID = Int(arguments[index + 1]),
              let fromX = Double(arguments[index + 2]), let fromY = Double(arguments[index + 3]),
              let toX = Double(arguments[index + 4]), let toY = Double(arguments[index + 5]) {
        preview.invocations.append(.drag(viewID, fromX, fromY, toX, toY))
        index += 6
    } else if option == "--wheel", index + 5 < arguments.count, let viewID = Int(arguments[index + 1]),
              let x = Double(arguments[index + 2]), let y = Double(arguments[index + 3]),
              let notchesX = Double(arguments[index + 4]), let notchesY = Double(arguments[index + 5]) {
        preview.invocations.append(.wheel(viewID, x, y, notchesX, notchesY))
        index += 6
    } else if option == "--expect-width", index + 2 < arguments.count, let viewID = Int(arguments[index + 1]),
              let width = Double(arguments[index + 2]) {
        preview.invocations.append(.expectWidth(viewID, width))
        index += 3
    } else if option == "--invoke-menu-item", index + 2 < arguments.count, let viewID = Int(arguments[index + 1]),
              let item = Int(arguments[index + 2]) {
        preview.invocations.append(.invokeMenuItem(viewID, item))
        index += 3
    } else if option == "--toggle-menu-item", index + 2 < arguments.count, let viewID = Int(arguments[index + 1]),
              let item = Int(arguments[index + 2]) {
        preview.invocations.append(.toggleMenuItem(viewID, item))
        index += 3
    } else if option == "--set-property", index + 3 < arguments.count, let viewID = Int(arguments[index + 1]) {
        preview.invocations.append(.setProperty(viewID, arguments[index + 2], arguments[index + 3]))
        index += 4
    } else if option == "--set-value", index + 2 < arguments.count, let viewID = Int(arguments[index + 1]) {
        preview.invocations.append(.setValue(viewID, arguments[index + 2]))
        index += 3
    } else if option == "--set-path", index + 2 < arguments.count, let viewID = Int(arguments[index + 1]),
              let ids = pathIDs(arguments[index + 2]) {
        preview.invocations.append(.setPath(viewID, ids))
        index += 3
    } else if option == "--set-state", index + 3 < arguments.count, let viewID = Int(arguments[index + 1]) {
        preview.invocations.append(.setState(viewID, arguments[index + 2], arguments[index + 3]))
        index += 4
    } else if option == "--expect-state", index + 3 < arguments.count, let viewID = Int(arguments[index + 1]) {
        preview.invocations.append(.expectState(viewID, arguments[index + 2], arguments[index + 3]))
        index += 4
    } else if option == "--expect-automation", index + 3 < arguments.count, let viewID = Int(arguments[index + 1]),
              ["name", "help", "id", "accelerator"].contains(arguments[index + 2]) {
        preview.invocations.append(.expectAutomation(viewID, arguments[index + 2], arguments[index + 3]))
        index += 4
    } else if option == "--delay", index + 1 < arguments.count, let milliseconds = Int(arguments[index + 1]), milliseconds >= 0 {
        preview.invocations.append(.delay(milliseconds))
        index += 2
    } else if option == "--wait" {
        preview.invocations.append(.wait)
        index += 1
    } else if option == "--add-rows", index + 3 < arguments.count, let viewID = Int(arguments[index + 1]),
              let count = Int(arguments[index + 2]), count >= 0 {
        preview.invocations.append(.addRows(viewID, count, arguments[index + 3]))
        index += 4
    } else if option == "--add-row", index + 2 < arguments.count, let viewID = Int(arguments[index + 1]) {
        preview.invocations.append(.addRow(viewID, arguments[index + 2]))
        index += 3
    } else if option == "--max-instances", index + 2 < arguments.count, let viewID = Int(arguments[index + 1]),
              let limit = Int(arguments[index + 2]) {
        preview.maxInstances[viewID] = limit
        index += 3
    } else if option == "--expect-action", index + 1 < arguments.count {
        preview.expectedActions.append(arguments[index + 1])
        index += 2
    } else if option == "--expect-log", index + 1 < arguments.count {
        expectedLogs.append(arguments[index + 1])
        index += 2
    } else if option == "--fetch-limit", index + 1 < arguments.count, let bytes = Int64(arguments[index + 1]), bytes > 0 {
        // A LoadableView's download refused past BYTES (default: the cap on ActionUI JSON).
        LoadableFetch.maximumBytes = bytes
        index += 2
    } else if option == "--configuration", index + 1 < arguments.count {
        // The host's configuration, as JSON (ActionUIConfiguration.set(json:)), before the document loads.
        do {
            try ActionUIConfiguration.set(json: arguments[index + 1])
        } catch {
            print("preview: the configuration was refused: \(error)")
            exit(64)
        }
        index += 2
    } else if option == "--refuse-remote-loads" {
        // A host policy that refuses every LoadableView's remote load (ActionUICapability.load).
        ActionUIModel.shared.trustPolicy = RefusingRemoteLoads()
        index += 1
    } else if option == "--no-launch" {
        // Links log what they would open (the renderer's "Link N: opening URL") and open nothing, so a run
        // starts no browser or other app.
        URLLauncher.launch = { url in
            ActionUIModel.shared.logger.log("preview: not launching \(url) (--no-launch)", .info)
            return true
        }
        index += 1
    } else if option == "--forbid-action", index + 1 < arguments.count {
        preview.forbiddenActions.append(arguments[index + 1])
        index += 2
    } else if option == "--on-action", index + 3 < arguments.count, let viewID = Int(arguments[index + 2]) {
        preview.valuesOnAction[arguments[index + 1]] = (viewID, arguments[index + 3])
        index += 4
    } else {
        print("preview: cannot read the option \(option)")
        print(usage)
        exit(64)
    }
}
_ = preview.pngPath.withCString(encodedAs: UTF16.self) { _wremove($0) }
let recordingLogger = RecordingLogger(forwardingTo: ActionUIModel.shared.logger)
if !expectedLogs.isEmpty {
    ActionUIModel.shared.logger = recordingLogger
}

guard actionUIWinUIInitialize() else {
    print("preview: \(WinUIError.last("initializing the Windows App SDK runtime"))")
    exit(1)
}
let ran = actionUIWinUIRun({ _ in
    MainActor.assumeIsolated { Preview.shared.launched() }
}, nil)
if !ran {
    print("preview: \(WinUIError.last("running WinUI"))")
}
actionUIWinUIShutdown()

let size = fileSize(preview.pngPath)
let missing = preview.expectedActions.filter { !preview.firedActions.contains($0) }
if !missing.isEmpty {
    print("preview: expected actions that did not fire: \(missing)")
}
let unlogged = expectedLogs.filter { text in !recordingLogger.messages.contains { $0.contains(text) } }
if !unlogged.isEmpty {
    print("preview: expected log messages that were not logged: \(unlogged)")
}
let forbidden = preview.forbiddenActions.filter { preview.firedActions.contains($0) }
if !forbidden.isEmpty {
    print("preview: actions that must not fire fired: \(forbidden)")
}
print("preview: run \(ran ? "ok" : "failed"), rendered \(preview.rendered ? "yes" : "no"), PNG \(size) bytes, actions fired \(preview.firedActions.count)")
exit(ran && preview.rendered && size > 0 && missing.isEmpty && unlogged.isEmpty && forbidden.isEmpty && preview.invocationsWorked
     && preview.instancesWithinLimit ? 0 : 1)
