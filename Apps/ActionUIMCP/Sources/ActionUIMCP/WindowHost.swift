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
// File panels are in WindowHost+Panels.swift. The windows themselves belong to the platform layer
// (WindowPlatform.swift).

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Dispatch
import ActionUI
import ActionUISwiftAdapter
import MCPStdio

@MainActor
final class WindowHost {
    static let maxWindows = 8
    static let maxQueuedEvents = 1000
    nonisolated static let maxNoticeLength = 1000

    enum Sizing {
        /// The content's fitting size, clamped to the screen.
        case fitting(resizable: Bool)
        /// This content size; the window is resizable.
        case fixed(ContentSize)
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
    let platform = HostPlatform()
    /// The ids of the open windows.
    var windows: Set<String> = []
    var dialogs: [String: DialogSession] = [:]
    /// Open panels count as something on screen.
    var openPanels = 0
    /// Staged document files of windows opened with `keep`, handed to a keeper process at shutdown
    /// (KeptWindows.swift).
    var keptDocuments: [String: URL] = [:]
    /// Properties update_window set, per window and element id, so a kept window's keeper sets
    /// them again over its staged document (KeptWindows.swift).
    var agentProperties: [String: [Int: [String: JSONValue]]] = [:]
    private let documentDirectory: URL

    /// Queued events per event window. A closed window's queue stays until it has been drained.
    private var eventQueues: [String: [Event]] = [:]
    private var droppedEvents: [String: Int] = [:]
    private var nextSequence = 0
    private var waiters: [UUID: Waiter] = [:]
    private var nextWaiterOrder = 0

    init(logger: HostLogger) {
        self.logger = logger
        documentDirectory = HostSupport.sessionFolder
        platform.host = self
    }

    /// Routes every ActionUI action to this host. Call once at launch.
    func install() {
        ActionUISwift.setDefaultActionHandler { [weak self] actionID, windowUUID, viewID, viewPartID, context in
            MainActor.assumeIsolated {
                self?.handleAction(actionID: actionID, windowUUID: windowUUID, viewID: viewID, part: viewPartID, context: context)
            }
        }
    }

    /// False without a graphical session (SSH, some remote environments); then no window can ever
    /// appear and a dialog would wait forever.
    var hasGraphicalSession: Bool {
        platform.hasGraphicalSession
    }

    // MARK: Windows

    /// Opens a window showing `document` and returns its id with the warnings ActionUI logged while
    /// loading it. With `rejectLoadErrors`, a document ActionUI logs errors for is not shown and the
    /// errors are thrown. `activate` takes the keyboard focus (dialogs need an answer). A `keep`
    /// window stays open after the session ends, in a keeper process (KeptWindows.swift).
    func openWindow(document: [String: Any], title: String, subtitle: String, sizing: Sizing, activate: Bool,
                    queuesEvents: Bool, rejectLoadErrors: Bool = false, keep: Bool = false) throws -> (id: String, warnings: [String]) {
        guard windows.count < Self.maxWindows else {
            throw MCPToolError("too many open windows (\(Self.maxWindows)); close one with close_window first")
        }
        let windowID = UUID().uuidString
        let loaded = try load(document: document, windowID: windowID, retainFile: keep)
        let errors = loaded.entries.filter { $0.level == .error }.map(\.message)
        if rejectLoadErrors && !errors.isEmpty {
            if let file = loaded.file { try? FileManager.default.removeItem(at: file) }
            forgetModel(windowID)
            throw MCPToolError("ActionUI could not load the document:\n" + errors.prefix(20).joined(separator: "\n"))
        }

        windows.insert(windowID)
        keptDocuments[windowID] = loaded.file
        if queuesEvents { eventQueues[windowID] = [] }
        updatePresence()
        // A layer that builds the document as it shows it logs the renderer's warnings here.
        let shown = logger.capture {
            platform.present(loaded.content, windowID: windowID, title: title, subtitle: subtitle, sizing: sizing, activate: activate)
        }
        #if DEBUG
        scheduleTestAction(windowID: windowID)
        #endif
        var seen: Set<String> = []
        let warnings = (loaded.entries + shown.entries).filter { $0.level == .warning || $0.level == .error }
            .map(\.message).filter { seen.insert($0).inserted }
        return (windowID, Array(warnings.prefix(20)))
    }

    /// Loads a document without showing it, for validate_document. Returns what ActionUI logged.
    func check(document: [String: Any]) throws -> (errors: [String], warnings: [String]) {
        let windowID = UUID().uuidString
        let loaded = try load(document: document, windowID: windowID)
        forgetModel(windowID)
        return (loaded.entries.filter { $0.level == .error }.map(\.message),
                loaded.entries.filter { $0.level == .warning }.map(\.message))
    }

    /// Stages the document through a private temporary file (the public loading API takes a URL)
    /// and loads it through the platform layer inside the log capture. With `retainFile` the staged
    /// file is left in place and returned, for a kept window.
    func load(document: [String: Any], windowID: String, retainFile: Bool = false) throws
        -> (content: HostPlatform.Content, entries: [HostLogger.Entry], file: URL?) {
        let fileURL = documentDirectory.appendingPathComponent(windowID + ".json")
        do {
            try FileManager.default.createDirectory(at: documentDirectory, withIntermediateDirectories: true)
            try Data(JSONValue(any: document).serialized().utf8).write(to: fileURL, options: .atomic)
        } catch {
            throw MCPToolError("could not stage the window document: \(error.displayText)")
        }
        defer {
            // ACTIONUI_MCP_KEEP_DOCUMENTS=1 leaves the staged files in place, to inspect or render
            // them with ActionUIViewer. A kept window's file stays for the keeper process and is
            // removed when the window closes.
            if ProcessInfo.processInfo.environment["ACTIONUI_MCP_KEEP_DOCUMENTS"] == "1" {
                HostSupport.logLine("[actionui-mcp] kept document \(fileURL.path)")
            } else if !retainFile {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        // Local loading is synchronous, so the file can go as soon as the view is built.
        let captured = logger.capture { platform.loadContent(file: fileURL, windowID: windowID) }
        return (captured.result, captured.entries, retainFile ? fileURL : nil)
    }

    /// Closes a window. Returns false when there is no such window.
    @discardableResult
    func closeWindow(_ windowID: String) -> Bool {
        guard windows.contains(windowID) else { return false }
        platform.close(windowID)  // windowClosed does the bookkeeping.
        return true
    }

    /// The platform layer's report that a window is closing, whoever closed it.
    func windowClosed(_ windowID: String) {
        windows.remove(windowID)
        agentProperties[windowID] = nil
        if let file = keptDocuments.removeValue(forKey: windowID) {
            try? FileManager.default.removeItem(at: file)
        }
        // The red close button or Cmd-W on a waiting dialog.
        if let session = dialogs[windowID], session.result == nil {
            settle(windowID, result: ["action": "cancel", "button": .null])
        }
        if eventQueues[windowID] != nil {
            enqueue(window: windowID, action: "window.closed", viewID: 0, part: 0, value: nil, context: nil)
        }
        if !HostPlatform.removesClosedWindowModels { forgetModel(windowID) }
        updatePresence()
    }

    /// Removes a window's ActionUI model once its window is gone, so a long session does not keep
    /// every document it showed, rendered or validated. After this turn of the run loop: views
    /// still updating as the window closes find their model. Every value an agent gets is read
    /// before the window closes (dialog results, events, a kept window's snapshot), and get_values
    /// refuses a closed window.
    func forgetModel(_ windowID: String) {
        DispatchQueue.main.async {
            ActionUISwift.removeWindow(windowUUID: windowID)
        }
    }

    /// Tells the platform layer whether there is a window or panel to click.
    func updatePresence() {
        platform.setShowsInterface(!windows.isEmpty || openPanels > 0)
    }

    func requireWindow(_ windowID: String) throws {
        guard windows.contains(windowID) else {
            throw MCPToolError("no open window \(windowID); it may have been closed")
        }
    }

    // MARK: Notices

    /// Shows a notice for `duration` seconds. Not a window: it does not count toward the window cap.
    func showNotice(title: String?, message: String, subtitle: String, duration: Double) throws {
        try platform.showNotice(title: title, message: message, subtitle: subtitle, duration: duration)
    }

    // MARK: Actions

    private func handleAction(actionID: String, windowUUID: String, viewID: Int, part: Int, context: Any?) {
        if dialogs[windowUUID] != nil {
            handleDialogAction(actionID: actionID, windowUUID: windowUUID)
        } else if eventQueues[windowUUID] != nil, windows.contains(windowUUID) {
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
            if !windows.contains(key) {
                eventQueues[key] = nil  // closed and now drained
            } else if eventQueues[key] != nil {
                eventQueues[key] = []
            }
        }
        events.sort { $0.sequence < $1.sequence }
        let list: [JSONValue] = events.map { event in
            var object: [String: JSONValue] = ["window": .string(event.window), "action": .string(event.action),
                                               "at": .string(HostSupport.preciseTimestamp(event.time))]
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
            return .string(HostSupport.timestamp(value))
        case let value as [String]: return .array(value.map(JSONValue.string))
        case let value as [[String]]: return .array(value.map { .array($0.map(JSONValue.string)) })
        case let value as AttributedString: return .string(String(value.characters))
        default:
            return ActionUISwift.getElementValueAsString(windowUUID: windowID, viewID: viewID).map(JSONValue.string)
        }
    }

    /// Writes values and table rows into an open window. Returns the problems, one per bad entry.
    /// Applies properties, then values, then rows (so a replaced chart description is in place
    /// before rows streamed in the same call). Returns the number of entries written, the refused
    /// entries and verifier warnings.
    func update(windowID: String, properties: [String: JSONValue], values: [String: JSONValue], rows: [String: JSONValue],
                appendRows: [String: JSONValue]) throws -> (updated: Int, problems: [String], warnings: [String]) {
        try requireWindow(windowID)
        // Entries written: each property, value and rows entry counts one.
        var updated = 0
        var problems: [String] = []
        var warnings: [String] = []
        func element(_ key: String) -> Int? {
            guard let id = Int(key), ActionUISwift.hasElement(windowUUID: windowID, viewID: id) else {
                problems.append("no element with id \(key)")
                return nil
            }
            return id
        }
        let types = properties.isEmpty && values.isEmpty ? [:] : ActionUISwift.getElementInfo(windowUUID: windowID)
        for (key, value) in properties.sorted(by: { $0.key < $1.key }) {
            guard let id = element(key) else { continue }
            guard let named = value.object, !named.isEmpty else {
                problems.append("id \(key): properties must be an object of property names to values")
                continue
            }
            guard let type = types[id] else {
                problems.append("id \(key): the element's type is unknown")
                continue
            }
            for (name, propertyValue) in named.sorted(by: { $0.key < $1.key }) {
                let check = AgentDocument.checkProperty(type: type, id: id, name: name, value: propertyValue)
                warnings += check.warnings
                if let refusal = check.refusal {
                    problems.append(refusal)
                    continue
                }
                ActionUISwift.setElementProperty(windowUUID: windowID, viewID: id, propertyName: name, value: check.value.any)
                agentProperties[windowID, default: [:]][id, default: [:]][name] = check.value
                updated += 1
            }
        }
        for (key, value) in values.sorted(by: { $0.key < $1.key }) {
            guard let id = element(key) else { continue }
            // A LoadableView's value is its source. Agent documents cannot contain one; this keeps
            // any other window's from loading a document the checks never saw.
            if types[id] == "LoadableView" {
                problems.append("id \(key) (LoadableView): \(AgentDocument.loadableViewRefusal)")
                continue
            }
            let text: String
            switch value {
            case .string(let string): text = string
            case .int, .double, .bool: text = DialogSpec.text(of: value)
            default:
                problems.append("id \(key): values must be strings, numbers or booleans")
                continue
            }
            ActionUISwift.setElementValueFromString(windowUUID: windowID, viewID: id, value: text)
            updated += 1
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
                updated += 1
            }
        }
        return (updated, problems, warnings)
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
            guard let self, self.windows.contains(windowID) else { return }
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
