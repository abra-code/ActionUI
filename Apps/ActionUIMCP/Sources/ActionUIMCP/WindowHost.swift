// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// WindowHost.swift - owns the windows the tools open. Everything here runs on the main actor; tool
// handlers reach it with `await`. A blocking dialog is a session: the window is open, the tool call
// awaits a continuation, and the first closing event (a dialog button, the window's close button,
// the timeout, or cancellation of the call) settles it exactly once.

import AppKit
import SwiftUI
import ActionUI
import ActionUISwiftAdapter
import MCPStdio

@MainActor
final class WindowHost: NSObject, NSWindowDelegate {
    static let maxWindows = 8

    private final class DialogSession {
        let spec: DialogSpec
        var continuation: CheckedContinuation<JSONValue, Never>?
        /// Set once, by the first closing event.
        var result: JSONValue?
        var timeoutTask: Task<Void, Never>?

        init(spec: DialogSpec) { self.spec = spec }
    }

    private var windows: [String: NSWindow] = [:]
    /// The hosting controllers own the SwiftUI trees; kept for the window's lifetime.
    private var controllers: [String: NSViewController] = [:]
    private var dialogs: [String: DialogSession] = [:]
    private let documentDirectory: URL

    override init() {
        documentDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("actionui-mcp-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        super.init()
    }

    /// Routes every ActionUI action to this host. Call once at launch.
    func install() {
        ActionUISwift.setDefaultActionHandler { [weak self] actionID, windowUUID, _, _, _ in
            MainActor.assumeIsolated {
                self?.handleAction(actionID: actionID, windowUUID: windowUUID)
            }
        }
    }

    /// False without a window server session (SSH, some remote environments); then no window can
    /// ever appear and a dialog would wait forever.
    var hasGraphicalSession: Bool {
        CGSessionCopyCurrentDictionary() != nil
    }

    var openWindowIDs: [String] {
        windows.keys.sorted()
    }

    // MARK: Windows

    /// Opens a window showing `document`. With `size` nil the window takes the content's fitting
    /// size and is not resizable (dialogs); otherwise it is a resizable viewer of that content size.
    /// `activate` brings the app to the front (dialogs need an answer); a viewer only orders its
    /// window front, so it does not take keyboard focus from whatever the user is typing in.
    func openWindow(document: [String: Any], title: String, subtitle: String, size: NSSize?, activate: Bool) throws -> String {
        guard windows.count < Self.maxWindows else {
            throw MCPToolError("too many open windows (\(Self.maxWindows)); close one with close_window first")
        }
        let windowID = UUID().uuidString
        // The public loading API takes a URL, so the document goes through a private temporary
        // file. Local loading is synchronous, so the file can go as soon as the view is built.
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

        let controller = ActionUISwift.loadHostingController(from: fileURL, windowUUID: windowID, isContentView: true)
        var style: NSWindow.StyleMask = [.titled, .closable]
        if size != nil { style.formUnion([.miniaturizable, .resizable]) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: size?.width ?? 400, height: size?.height ?? 200),
                              styleMask: style, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = title
        window.subtitle = subtitle
        window.contentView = controller.view
        if let size {
            window.setContentSize(size)
        } else {
            let fitting = controller.view.fittingSize
            if fitting.width > 0 && fitting.height > 0 {
                window.setContentSize(fitting)
            }
        }
        window.delegate = self
        window.center()

        windows[windowID] = window
        controllers[windowID] = controller
        updateActivationPolicy()
        if activate {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFrontRegardless()
        }
        return windowID
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
        updateActivationPolicy()
    }

    /// A Dock icon and menu bar only while there is a window to click.
    private func updateActivationPolicy() {
        let wanted: NSApplication.ActivationPolicy = windows.isEmpty ? .accessory : .regular
        if NSApp.activationPolicy() != wanted {
            NSApp.setActivationPolicy(wanted)
        }
    }

    // MARK: Dialogs

    /// Opens a dialog window and registers its session. The caller then awaits result(of:).
    func beginDialog(spec: DialogSpec, subtitle: String, timeout: Double) throws -> String {
        let document = spec.document(footer: "Your answers are sent to the AI agent that asked.")
        let windowID = try openWindow(document: document, title: spec.title, subtitle: subtitle, size: nil, activate: true)
        // Picker has no property for its initial selection; set it through the value API.
        for field in spec.fields where field.kind == .choice {
            if let tag = field.defaultValue?.string, field.options.contains(where: { $0.tag == tag }) {
                ActionUISwift.setElementValue(windowUUID: windowID, viewID: field.viewID, value: tag)
            }
        }
        let session = DialogSession(spec: spec)
        dialogs[windowID] = session
        session.timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.settle(windowID, result: ["action": "timeout", "button": .null])
        }
        #if DEBUG
        // Test hook for sessions with no one at the screen: ACTIONUI_MCP_TEST_PRESS="<button title>"
        // presses that button 1.5 s after the dialog opens, through the same path as a click.
        if let title = ProcessInfo.processInfo.environment["ACTIONUI_MCP_TEST_PRESS"],
           let button = spec.buttons.first(where: { $0.title == title }) {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self?.handleAction(actionID: button.actionID, windowUUID: windowID)
            }
        }
        #endif
        return windowID
    }

    /// Waits for the dialog's outcome. Cancelling the calling task (the client sent
    /// notifications/cancelled, or the session ended) closes the dialog.
    nonisolated func result(of windowID: String) async -> JSONValue {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                Task { @MainActor in self.attach(windowID, continuation) }
            }
        } onCancel: {
            Task { @MainActor in self.settle(windowID, result: ["action": "cancel", "button": .null]) }
        }
    }

    /// Hands the waiting continuation to the session, or resumes it at once when the dialog was
    /// settled before the caller got here. Main actor only, so it cannot race settle().
    private func attach(_ windowID: String, _ continuation: CheckedContinuation<JSONValue, Never>) {
        guard let session = dialogs[windowID] else {
            continuation.resume(returning: ["action": "cancel", "button": .null])
            return
        }
        if let result = session.result {
            dialogs[windowID] = nil
            continuation.resume(returning: result)
        } else {
            session.continuation = continuation
        }
    }

    /// Records the first outcome, closes the window, and resumes the waiter if it is attached.
    private func settle(_ windowID: String, result: JSONValue) {
        guard let session = dialogs[windowID], session.result == nil else { return }
        session.result = result
        session.timeoutTask?.cancel()
        closeWindow(windowID)
        if let continuation = session.continuation {
            dialogs[windowID] = nil
            continuation.resume(returning: result)
        }
    }

    private func handleAction(actionID: String, windowUUID: String) {
        guard let session = dialogs[windowUUID], session.result == nil,
              actionID.hasPrefix(DialogSpec.buttonActionPrefix),
              let index = Int(actionID.dropFirst(DialogSpec.buttonActionPrefix.count)),
              session.spec.buttons.indices.contains(index) else { return }
        let button = session.spec.buttons[index]
        if button.isCancel {
            settle(windowUUID, result: ["action": "cancel", "button": .string(button.title)])
            return
        }
        let snapshot = values(of: session.spec, windowID: windowUUID)
        var problems: [String] = []
        if !snapshot.missing.isEmpty { problems.append("Please fill in: " + snapshot.missing.joined(separator: ", ")) }
        if !snapshot.invalid.isEmpty { problems.append("Not a number: " + snapshot.invalid.joined(separator: ", ")) }
        if !problems.isEmpty {
            ActionUISwift.presentToast(windowUUID: windowUUID, message: problems.joined(separator: ". "))
            return
        }
        settle(windowUUID, result: ["action": "accept", "button": .string(button.title), "values": .object(snapshot.values)])
    }

    // MARK: Value snapshot

    /// Reads every field's current value, typed per field kind. A control the user never touched
    /// may have no stored value yet; it then reports the default it was drawn with.
    private func values(of spec: DialogSpec, windowID: String) -> (values: [String: JSONValue], missing: [String], invalid: [String]) {
        var values: [String: JSONValue] = [:]
        var missing: [String] = []
        var invalid: [String] = []
        for field in spec.fields {
            let raw = ActionUISwift.getElementValue(windowUUID: windowID, viewID: field.viewID)
            let value: JSONValue
            switch field.kind {
            case .text, .multiline:
                let text = raw as? String ?? field.defaultValue.map(DialogSpec.text(of:)) ?? ""
                value = .string(text)
                if field.required && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.append(field.label) }
            case .number, .integer:
                let text = (raw as? String ?? field.defaultValue.map(DialogSpec.text(of:)) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    value = .null
                    if field.required { missing.append(field.label) }
                } else if let number = Self.parseNumber(text, integer: field.kind == .integer) {
                    value = number
                } else {
                    value = .string(text)
                    invalid.append(field.label)
                }
            case .toggle:
                value = .bool(raw as? Bool ?? field.defaultValue?.bool ?? false)
            case .choice:
                let tag = raw as? String ?? field.defaultValue?.string
                let known = tag.flatMap { tag in field.options.contains(where: { $0.tag == tag }) ? tag : nil }
                value = .string(known ?? field.options[0].tag)
            case .slider:
                value = .double(raw as? Double ?? field.defaultValue?.double ?? field.min ?? 0)
            case .date:
                if let date = raw as? Date {
                    value = .string(Self.dayFormatter.string(from: date))
                } else if let text = field.defaultValue?.string {
                    value = .string(text)
                } else {
                    value = .null
                    if field.required { missing.append(field.label) }
                }
            }
            values[field.key] = value
        }
        return (values, missing, invalid)
    }

    /// Accepts what a person types: "1234", "1,234.5" in the user's locale, or "1234.5".
    private static func parseNumber(_ text: String, integer: Bool) -> JSONValue? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let number = formatter.number(from: text)?.doubleValue ?? Double(text)
        guard let number, number.isFinite else { return nil }
        if integer {
            guard number == number.rounded(), abs(number) < 9e15 else { return nil }
            return .int(Int(number))
        }
        return .double(number)
    }

    /// Dates come back as the calendar day the user picked, in their time zone.
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
