// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// WindowHost+Dialogs.swift - blocking dialogs. A dialog is a session: the window is open, the
// tool call awaits a continuation, and the first closing event (a dialog button, a declared close
// action, the window's close button, the timeout, or cancellation of the call) settles it exactly
// once. Canned dialogs (ask_user) report typed field values; agent documents (show_document in
// dialog mode) report the value of every element with an id.

import AppKit
import ActionUI
import ActionUISwiftAdapter
import MCPStdio

@MainActor
final class DialogSession {
    enum Kind {
        case canned(DialogSpec)
        case document(DocumentDialog)
    }

    let kind: Kind
    var continuation: CheckedContinuation<JSONValue, Never>?
    /// Set once, by the first closing event.
    var result: JSONValue?
    var timeoutTask: Task<Void, Never>?

    init(kind: Kind) { self.kind = kind }

    var buttons: [DialogButton] {
        switch kind {
        case .canned(let spec): return spec.buttons
        case .document(let dialog): return dialog.buttons
        }
    }
}

extension WindowHost {
    static let dialogFooter = "Your answers are sent to the AI agent that asked."

    /// Opens an ask_user dialog and registers its session. The caller then awaits result(of:).
    func beginDialog(spec: DialogSpec, subtitle: String, timeout: Double) throws -> String {
        let windowID = try openWindow(document: spec.document(footer: Self.dialogFooter), title: spec.title,
                                      subtitle: subtitle, sizing: .fitting(resizable: false), activate: true,
                                      queuesEvents: false).id
        // Picker has no property for its initial selection; set it through the value API.
        for field in spec.fields where field.kind == .choice {
            if let tag = field.defaultValue?.string, field.options.contains(where: { $0.tag == tag }) {
                ActionUISwift.setElementValue(windowUUID: windowID, viewID: field.viewID, value: tag)
            }
        }
        register(DialogSession(kind: .canned(spec)), windowID: windowID, timeout: timeout)
        return windowID
    }

    /// Opens an agent document inside dialog chrome and registers its session.
    func beginDocumentDialog(document: AgentDocument, dialog: DocumentDialog, title: String, subtitle: String,
                             size: NSSize?, timeout: Double) throws -> (id: String, warnings: [String]) {
        let opened = try openWindow(document: dialog.wrap(document.foundation, footer: Self.dialogFooter), title: title,
                                    subtitle: subtitle, sizing: size.map { .fixed($0) } ?? .fitting(resizable: true),
                                    activate: true, queuesEvents: false, rejectLoadErrors: true)
        register(DialogSession(kind: .document(dialog)), windowID: opened.id, timeout: timeout)
        return opened
    }

    private func register(_ session: DialogSession, windowID: String, timeout: Double) {
        dialogs[windowID] = session
        session.timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.settle(windowID, result: ["action": "timeout", "button": .null])
        }
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
    func settle(_ windowID: String, result: JSONValue) {
        guard let session = dialogs[windowID], session.result == nil else { return }
        session.result = result
        session.timeoutTask?.cancel()
        closeWindow(windowID)
        if let continuation = session.continuation {
            dialogs[windowID] = nil
            continuation.resume(returning: result)
        }
    }

    func handleDialogAction(actionID: String, windowUUID: String) {
        guard let session = dialogs[windowUUID], session.result == nil else { return }
        if actionID.hasPrefix(DialogSpec.sliderActionPrefix), case .canned(let spec) = session.kind {
            updateSliderReadout(actionID: actionID, windowUUID: windowUUID, spec: spec)
            return
        }
        if case .document(let dialog) = session.kind, dialog.closeActions.contains(actionID) {
            settle(windowUUID, result: ["action": "accept", "button": .null, "close_action": .string(actionID),
                                        "values": .object(values(windowID: windowUUID, ids: nil))])
            return
        }
        guard actionID.hasPrefix(DialogSpec.buttonActionPrefix),
              let index = Int(actionID.dropFirst(DialogSpec.buttonActionPrefix.count)),
              session.buttons.indices.contains(index) else { return }
        let button = session.buttons[index]
        if button.isCancel {
            settle(windowUUID, result: ["action": "cancel", "button": .string(button.title)])
            return
        }
        switch session.kind {
        case .document:
            settle(windowUUID, result: ["action": "accept", "button": .string(button.title),
                                        "values": .object(values(windowID: windowUUID, ids: nil))])
        case .canned(let spec):
            let snapshot = fieldValues(of: spec, windowID: windowUUID)
            var problems: [String] = []
            if !snapshot.missing.isEmpty { problems.append("Please fill in: " + snapshot.missing.joined(separator: ", ")) }
            if !snapshot.invalid.isEmpty { problems.append("Not a number: " + snapshot.invalid.joined(separator: ", ")) }
            if !problems.isEmpty {
                ActionUISwift.presentToast(windowUUID: windowUUID, message: problems.joined(separator: ". "))
                return
            }
            settle(windowUUID, result: ["action": "accept", "button": .string(button.title),
                                        "values": .object(snapshot.values)])
        }
    }

    /// ActionUI's Slider has no value label; the dialog puts a Text beside it and keeps it current.
    private func updateSliderReadout(actionID: String, windowUUID: String, spec: DialogSpec) {
        guard let viewID = Int(actionID.dropFirst(DialogSpec.sliderActionPrefix.count)),
              let field = spec.fields.first(where: { $0.viewID == viewID && $0.kind == .slider }),
              let value = ActionUISwift.getElementValue(windowUUID: windowUUID, viewID: viewID) as? Double else { return }
        ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: viewID + DialogSpec.readoutViewIDOffset,
                                      value: DialogSpec.readout(value, for: field))
    }

    // MARK: Viewers

    /// Opens a `show` window; a table gets its rows once the window exists. Viewers have no actions
    /// worth reporting, so they queue no events: a closed viewer leaves nothing behind for `wait`.
    func openViewer(spec: ViewerSpec, subtitle: String, keep: Bool) throws -> String {
        let windowID = try openWindow(document: spec.root, title: spec.title, subtitle: subtitle,
                                      sizing: .fixed(NSSize(width: spec.width, height: spec.height)),
                                      activate: false, queuesEvents: false, keep: keep).id
        if let rows = spec.tableRows, !rows.isEmpty {
            ActionUISwift.setElementRows(windowUUID: windowID, viewID: ViewerSpec.tableViewID, rows: rows)
        }
        return windowID
    }

    // MARK: Field values

    /// Reads every ask_user field's current value, typed per field kind. A control the user never
    /// touched may have no stored value yet; it then reports the default it was drawn with.
    private func fieldValues(of spec: DialogSpec, windowID: String) -> (values: [String: JSONValue], missing: [String], invalid: [String]) {
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
