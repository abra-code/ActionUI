// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// WindowHost.swift - owns the windows the tools open. Everything here runs on the main actor; tool
// handlers reach it with `await`. Two kinds of window:
// - dialogs (WindowHost+Dialogs.swift): a tool call waits for the first closing event;
// - event windows (show_document in window mode): every ActionUI action in them is queued
//   per window, and the `wait` tool hands the queued events to the agent.
// File panels are in WindowHost+Panels.swift.

import AppKit
import SwiftUI
import ActionUI
import ActionUISwiftAdapter
import MCPStdio

@MainActor
final class WindowHost: NSObject, NSWindowDelegate {
    static let maxWindows = 8
    static let maxQueuedEvents = 1000

    enum Sizing {
        /// The content's fitting size, clamped to the screen.
        case fitting(resizable: Bool)
        /// This content size; the window is resizable.
        case fixed(NSSize)
    }

    struct Event {
        let sequence: Int
        let window: String
        let action: String
        let viewID: Int
        let part: Int
        var value: JSONValue?
        var context: JSONValue?
        var count: Int
        var time: Date
    }

    private final class Waiter {
        let window: String?
        /// Arrival order; events go to the oldest matching waiter.
        let order: Int
        var continuation: CheckedContinuation<JSONValue, Never>?
        var timeoutTask: Task<Void, Never>?
        /// The call was cancelled before its continuation attached.
        var cancelled = false
        init(window: String?, order: Int) {
            self.window = window
            self.order = order
        }
    }

    let logger: HostLogger
    var windows: [String: NSWindow] = [:]
    /// The hosting controllers own the SwiftUI trees; kept for the window's lifetime.
    private var controllers: [String: NSViewController] = [:]
    var dialogs: [String: DialogSession] = [:]
    /// Open panels count toward the activation policy.
    var openPanels = 0
    private let documentDirectory: URL

    /// Queued events per event window. A closed window's queue stays until it has been drained.
    private var eventQueues: [String: [Event]] = [:]
    private var droppedEvents: [String: Int] = [:]
    private var nextSequence = 0
    private var waiters: [UUID: Waiter] = [:]
    private var nextWaiterOrder = 0

    init(logger: HostLogger) {
        self.logger = logger
        documentDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("actionui-mcp-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        super.init()
    }

    /// Routes every ActionUI action to this host. Call once at launch.
    func install() {
        ActionUISwift.setDefaultActionHandler { [weak self] actionID, windowUUID, viewID, viewPartID, context in
            MainActor.assumeIsolated {
                self?.handleAction(actionID: actionID, windowUUID: windowUUID, viewID: viewID, part: viewPartID, context: context)
            }
        }
    }

    /// False without a window server session (SSH, some remote environments); then no window can
    /// ever appear and a dialog would wait forever.
    var hasGraphicalSession: Bool {
        CGSessionCopyCurrentDictionary() != nil
    }

    // MARK: Windows

    /// Opens a window showing `document` and returns its id with the warnings ActionUI logged while
    /// loading it. With `rejectLoadErrors`, a document ActionUI logs errors for is not shown and the
    /// errors are thrown. `activate` brings the app to the front (dialogs need an answer); otherwise
    /// the window is only ordered front, so it does not take keyboard focus from the user.
    func openWindow(document: [String: Any], title: String, subtitle: String, sizing: Sizing, activate: Bool,
                    queuesEvents: Bool, rejectLoadErrors: Bool = false) throws -> (id: String, warnings: [String]) {
        guard windows.count < Self.maxWindows else {
            throw MCPToolError("too many open windows (\(Self.maxWindows)); close one with close_window first")
        }
        let windowID = UUID().uuidString
        let loaded = try load(document: document, windowID: windowID)
        let errors = loaded.entries.filter { $0.level == .error }.map(\.message)
        if rejectLoadErrors && !errors.isEmpty {
            throw MCPToolError("ActionUI could not load the document:\n" + errors.prefix(20).joined(separator: "\n"))
        }
        let controller = loaded.controller

        var style: NSWindow.StyleMask = [.titled, .closable]
        switch sizing {
        case .fitting(let resizable) where resizable: style.formUnion([.miniaturizable, .resizable])
        case .fixed: style.formUnion([.miniaturizable, .resizable])
        default: break
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                              styleMask: style, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = controller.view
        // After the content view: installing the SwiftUI hosting view resets the window's title
        // and subtitle, and the subtitle carries the provenance line.
        window.title = title
        window.subtitle = subtitle
        switch sizing {
        case .fixed(let size):
            window.setContentSize(size)
        case .fitting:
            window.setContentSize(Self.clampedToScreen(loaded.fitting))
        }
        window.delegate = self
        window.center()

        windows[windowID] = window
        controllers[windowID] = controller
        if queuesEvents { eventQueues[windowID] = [] }
        updateActivationPolicy()
        if activate {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFrontRegardless()
        }
        #if DEBUG
        scheduleTestAction(windowID: windowID)
        #endif
        let warnings = loaded.entries.filter { $0.level == .warning }.map(\.message)
        return (windowID, Array(warnings.prefix(20)))
    }

    /// Loads a document without showing it, for validate_document. Returns what ActionUI logged.
    /// Note: ActionUI keeps the model of every loaded document for the life of the process.
    func check(document: [String: Any]) throws -> (errors: [String], warnings: [String]) {
        let loaded = try load(document: document, windowID: UUID().uuidString)
        return (loaded.entries.filter { $0.level == .error }.map(\.message),
                loaded.entries.filter { $0.level == .warning }.map(\.message))
    }

    /// Stages the document through a private temporary file (the public loading API takes a URL),
    /// builds its view, and measures it once so that view construction runs inside the log capture.
    func load(document: [String: Any], windowID: String) throws
        -> (controller: NSViewController, fitting: NSSize, entries: [HostLogger.Entry]) {
        let fileURL = documentDirectory.appendingPathComponent(windowID + ".json")
        do {
            try FileManager.default.createDirectory(at: documentDirectory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: document)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw MCPToolError("could not stage the window document: \(error.localizedDescription)")
        }
        defer {
            // ACTIONUI_MCP_KEEP_DOCUMENTS=1 leaves the staged files in place, to inspect or render
            // them with ActionUIViewer.
            if ProcessInfo.processInfo.environment["ACTIONUI_MCP_KEEP_DOCUMENTS"] == "1" {
                FileHandle.standardError.write(Data("[actionui-mcp] kept document \(fileURL.path)\n".utf8))
            } else {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        // Local loading is synchronous, so the file can go as soon as the view is built.
        let captured = logger.capture {
            let controller = ActionUISwift.loadHostingController(from: fileURL, windowUUID: windowID, isContentView: true)
            return (controller, controller.view.fittingSize)
        }
        return (captured.result.0, captured.result.1, captured.entries)
    }

    static func clampedToScreen(_ size: NSSize) -> NSSize {
        let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let width = size.width > 0 ? size.width : 480
        let height = size.height > 0 ? size.height : 320
        return NSSize(width: min(max(width, 240), screen.width * 0.9),
                      height: min(max(height, 80), screen.height * 0.9))
    }

    /// Closes a window. Returns false when there is no such window.
    @discardableResult
    func closeWindow(_ windowID: String) -> Bool {
        guard let window = windows[windowID] else { return false }
        window.close()  // windowWillClose does the bookkeeping.
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let windowID = windows.first(where: { $0.value === window })?.key else { return }
        windows[windowID] = nil
        controllers[windowID] = nil
        // The red close button or Cmd-W on a waiting dialog.
        if let session = dialogs[windowID], session.result == nil {
            settle(windowID, result: ["action": "cancel", "button": .null])
        }
        if eventQueues[windowID] != nil {
            enqueue(window: windowID, action: "window.closed", viewID: 0, part: 0, value: nil, context: nil)
        }
        updateActivationPolicy()
    }

    /// A Dock icon and menu bar only while there is a window or panel to click.
    func updateActivationPolicy() {
        let wanted: NSApplication.ActivationPolicy = windows.isEmpty && openPanels == 0 ? .accessory : .regular
        if NSApp.activationPolicy() != wanted {
            NSApp.setActivationPolicy(wanted)
        }
    }

    func requireWindow(_ windowID: String) throws {
        guard windows[windowID] != nil else {
            throw MCPToolError("no open window \(windowID); it may have been closed")
        }
    }

    // MARK: Actions

    private func handleAction(actionID: String, windowUUID: String, viewID: Int, part: Int, context: Any?) {
        if dialogs[windowUUID] != nil {
            handleDialogAction(actionID: actionID, windowUUID: windowUUID)
        } else if eventQueues[windowUUID] != nil, windows[windowUUID] != nil {
            let value = viewID > 0 ? Self.json(ActionUISwift.getElementValue(windowUUID: windowUUID, viewID: viewID),
                                               windowID: windowUUID, viewID: viewID) : nil
            enqueue(window: windowUUID, action: actionID, viewID: viewID, part: part, value: value,
                    context: context.map { JSONValue(any: $0) }.flatMap { $0 == .null ? nil : $0 })
        }
    }

    // MARK: Events

    private func enqueue(window: String, action: String, viewID: Int, part: Int, value: JSONValue?, context: JSONValue?) {
        var queue = eventQueues[window] ?? []
        // A burst of the same action on the same element (a dragged slider, typing) becomes one
        // event carrying the latest value and a count.
        if var last = queue.last, last.action == action, last.viewID == viewID, last.part == part {
            last.value = value
            last.context = context
            last.count += 1
            last.time = Date()
            queue[queue.count - 1] = last
        } else {
            nextSequence += 1
            queue.append(Event(sequence: nextSequence, window: window, action: action, viewID: viewID, part: part,
                               value: value, context: context, count: 1, time: Date()))
            if queue.count > Self.maxQueuedEvents {
                queue.removeFirst()
                droppedEvents[window, default: 0] += 1
            }
        }
        eventQueues[window] = queue
        // Hand the events to the oldest matching waiter.
        let matching = waiters.filter { $0.value.continuation != nil && ($0.value.window == nil || $0.value.window == window) }
        if let (waiterID, _) = matching.min(by: { $0.value.order < $1.value.order }) {
            resolveWaiter(waiterID, result: drain(window: waiters[waiterID]?.window))
        }
        // A waiter older than that one took a closed window's last events: whoever still waits for
        // that window (or for any window, when none is left) would only time out.
        for (waiterID, waiter) in waiters where waiter.continuation != nil && hasNothingToWaitFor(waiter.window) {
            resolveWaiter(waiterID, result: drain(window: waiter.window))
        }
    }

    /// True when no event can come any more for `window` (or for any window).
    private func hasNothingToWaitFor(_ window: String?) -> Bool {
        window.map { eventQueues[$0] == nil } ?? eventQueues.isEmpty
    }

    /// Takes all queued events of one window (or of all windows), oldest first.
    private func drain(window: String?) -> JSONValue {
        let keys = window.map { [$0] } ?? Array(eventQueues.keys)
        var events: [Event] = []
        var dropped = 0
        for key in keys {
            events += eventQueues[key] ?? []
            dropped += droppedEvents[key] ?? 0
            droppedEvents[key] = nil
            if windows[key] == nil {
                eventQueues[key] = nil  // closed and now drained
            } else if eventQueues[key] != nil {
                eventQueues[key] = []
            }
        }
        events.sort { $0.sequence < $1.sequence }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let list: [JSONValue] = events.map { event in
            var object: [String: JSONValue] = ["window": .string(event.window), "action": .string(event.action),
                                               "at": .string(formatter.string(from: event.time))]
            if event.viewID > 0 { object["id"] = .int(event.viewID) }
            if event.part != 0 { object["part"] = .int(event.part) }
            if let value = event.value { object["value"] = value }
            if let context = event.context { object["context"] = context }
            if event.count > 1 { object["count"] = .int(event.count) }
            return .object(object)
        }
        return ["events": .array(list), "dropped": .int(dropped)]
    }

    /// Waits for events of one window or of any event window, up to `timeout` seconds. Returns at
    /// once when events are already queued.
    nonisolated func waitForEvents(window: String?, timeout: Double) async throws -> JSONValue {
        let waiterID = UUID()
        try await MainActor.run {
            if let window, eventQueues[window] == nil {
                throw MCPToolError("no window \(window) with events; it may have closed and its events were already returned")
            }
            if window == nil && eventQueues.isEmpty {
                throw MCPToolError("no open window sends events; open one with show_document first")
            }
            // Registered now, attached below: a cancellation arriving in between finds it.
            nextWaiterOrder += 1
            waiters[waiterID] = Waiter(window: window, order: nextWaiterOrder)
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                Task { @MainActor in self.attachWaiter(waiterID, timeout: timeout, continuation) }
            }
        } onCancel: {
            Task { @MainActor in
                guard let waiter = self.waiters[waiterID] else { return }  // already answered
                if waiter.continuation != nil {
                    self.resolveWaiter(waiterID, result: ["events": [], "dropped": 0, "cancelled": true])
                } else {
                    waiter.cancelled = true
                }
            }
        }
    }

    private func attachWaiter(_ waiterID: UUID, timeout: Double, _ continuation: CheckedContinuation<JSONValue, Never>) {
        guard let waiter = waiters[waiterID] else {
            continuation.resume(returning: ["events": [], "dropped": 0, "cancelled": true])
            return
        }
        let window = waiter.window
        if waiter.cancelled {
            waiters[waiterID] = nil
            continuation.resume(returning: ["events": [], "dropped": 0, "cancelled": true])
            return
        }
        // Events already queued, or the window closed and was drained since the call began.
        let keys = window.map { [$0] } ?? Array(eventQueues.keys)
        if keys.contains(where: { !(eventQueues[$0]?.isEmpty ?? true) }) || hasNothingToWaitFor(window) {
            waiters[waiterID] = nil
            continuation.resume(returning: drain(window: window))
            return
        }
        waiter.continuation = continuation
        waiter.timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.resolveWaiter(waiterID, result: ["events": [], "dropped": 0, "timed_out": true])
        }
    }

    private func resolveWaiter(_ waiterID: UUID, result: JSONValue) {
        guard let waiter = waiters.removeValue(forKey: waiterID) else { return }
        waiter.timeoutTask?.cancel()
        waiter.continuation?.resume(returning: result)
    }

    // MARK: Values

    /// Current values of the elements with ids (all of them, or `ids`), keyed by id. Elements that
    /// hold no value (stacks, text without a runtime value) are left out.
    func values(windowID: String, ids: [Int]?) -> [String: JSONValue] {
        let known = ActionUISwift.getElementInfo(windowUUID: windowID)
        var result: [String: JSONValue] = [:]
        for id in ids ?? known.keys.sorted() where known[id] != nil {
            if let value = Self.json(ActionUISwift.getElementValue(windowUUID: windowID, viewID: id), windowID: windowID, viewID: id) {
                result[String(id)] = value
            }
        }
        return result
    }

    /// An element value as JSON. Native Swift values map directly; anything else goes through
    /// ActionUI's own string form.
    static func json(_ raw: Any?, windowID: String, viewID: Int) -> JSONValue? {
        switch raw {
        case nil: return nil
        case let value as Bool: return .bool(value)
        case let value as Int: return .int(value)
        case let value as Double: return value.isFinite ? .double(value) : nil
        case let value as String: return .string(value)
        case let value as Date:
            return .string(ISO8601DateFormatter().string(from: value))
        case let value as [String]: return .array(value.map(JSONValue.string))
        case let value as [[String]]: return .array(value.map { .array($0.map(JSONValue.string)) })
        case let value as AttributedString: return .string(String(value.characters))
        default:
            return ActionUISwift.getElementValueAsString(windowUUID: windowID, viewID: viewID).map(JSONValue.string)
        }
    }

    /// Writes values and table rows into an open window. Returns the problems, one per bad entry.
    func update(windowID: String, values: [String: JSONValue], rows: [String: JSONValue],
                appendRows: [String: JSONValue]) throws -> [String] {
        try requireWindow(windowID)
        var problems: [String] = []
        func element(_ key: String) -> Int? {
            guard let id = Int(key), ActionUISwift.hasElement(windowUUID: windowID, viewID: id) else {
                problems.append("no element with id \(key)")
                return nil
            }
            return id
        }
        for (key, value) in values.sorted(by: { $0.key < $1.key }) {
            guard let id = element(key) else { continue }
            let text: String
            switch value {
            case .string(let string): text = string
            case .int, .double, .bool: text = DialogSpec.text(of: value)
            default:
                problems.append("id \(key): values must be strings, numbers or booleans")
                continue
            }
            ActionUISwift.setElementValueFromString(windowUUID: windowID, viewID: id, value: text)
        }
        for (table, append) in [(rows, false), (appendRows, true)] {
            for (key, value) in table.sorted(by: { $0.key < $1.key }) {
                guard let id = element(key) else { continue }
                guard let list = value.array, list.allSatisfy({ $0.array != nil }) else {
                    problems.append("id \(key): rows must be an array of arrays of cells")
                    continue
                }
                let cells = list.map { $0.array!.map(DialogSpec.text(of:)) }
                if append {
                    ActionUISwift.appendElementRows(windowUUID: windowID, viewID: id, rows: cells)
                } else {
                    ActionUISwift.setElementRows(windowUUID: windowID, viewID: id, rows: cells)
                }
            }
        }
        return problems
    }

    // MARK: Test hooks

    #if DEBUG
    /// For sessions with no one at the screen. 1.5 s after a window opens:
    /// ACTIONUI_MCP_TEST_PRESS="<button title>" presses that dialog button, and
    /// ACTIONUI_MCP_TEST_ACTION="<actionID>@<viewID>" fires that action, both through the same path
    /// as a click.
    private func scheduleTestAction(windowID: String) {
        let environment = ProcessInfo.processInfo.environment
        let press = environment["ACTIONUI_MCP_TEST_PRESS"]
        let action = environment["ACTIONUI_MCP_TEST_ACTION"]
        guard press != nil || action != nil else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, self.windows[windowID] != nil else { return }
            if let press, let button = self.dialogs[windowID]?.buttons.first(where: { $0.title == press }) {
                self.handleAction(actionID: button.actionID, windowUUID: windowID, viewID: 0, part: 0, context: nil)
            }
            if let action {
                let parts = action.split(separator: "@", maxSplits: 1)
                self.handleAction(actionID: String(parts[0]), windowUUID: windowID,
                                  viewID: parts.count > 1 ? Int(parts[1]) ?? 0 : 0, part: 0, context: nil)
            }
        }
    }
    #endif
}
