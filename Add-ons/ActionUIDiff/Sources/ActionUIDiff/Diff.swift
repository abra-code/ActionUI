// Add-ons/ActionUIDiff/Sources/ActionUIDiff/Diff.swift
/*
 Sample JSON for Diff:
 {
   "type": "Diff",
   "id": 1,                     // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "oldText": "func f() {}",           // Optional: Inline text for the OLD (left) side to compare
     "newText": "func f() { g() }",      // Optional: Inline text for the NEW (right) side to compare
     "oldFile": "~/before.swift",        // Optional: Absolute local path (tilde-expanded), read as UTF-8;
                                          //           used only when "oldText" is absent
     "newFile": "~/after.swift",         // Optional: Absolute local path (tilde-expanded), read as UTF-8;
                                          //           used only when "newText" is absent
     "contextLines": 3,                  // Optional: Int, default 3, >= 0; unchanged lines kept around each change
     "maxRenderedLines": 300             // Optional: Int, default 300, > 0; render cap before a truncation note
   }
 }

 An embedded unified line-diff viewer, implemented as an ActionUI add-on (registered via
 ActionUIDiff.register()). It renders the difference between two texts with the standalone DiffView
 component: hunks with old/new line-number gutters, +/- markers, tinted added/removed rows, "N
 unchanged lines" gaps where context collapsed, and honest degenerate cases (identical texts say "No
 changes"; oversized inputs fall back to a plain-text preview).

 DISPLAY-ONLY: the element has no observable value (valueType Void) - nothing to read back with
 getElementValue. What it shows lives entirely in its properties.

 All six properties are live: a setElementProperty after the element is displayed re-renders it. The
 wrapper is stateless - it builds the view from the current properties on every invocation, capturing
 nothing - so a host can drive the diff at runtime (e.g. inject oldFile / newFile paths resolved from
 a bundle) and the view updates.

 Per side, the text property WINS over the file property: if both "oldText" and "oldFile" are set the
 text is used and a warning is logged (same for the new side). A file path is tilde-expanded and read
 as UTF-8; a file that is missing, over 4 MB, or not valid UTF-8 renders an inline "Cannot read
 <path>" note instead of a misleading diff. A side with NEITHER text nor file is empty text - a
 legitimate new-file (all additions) or deleted-file (all removals) diff.

 Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity,
 cornerRadius, actionID, disabled, onAppearActionID, onDisappearActionID, etc.) are inherited from base View.

 Implementation note: conforms to ActionUI's public ActionUIViewConstruction contract. The type and its
 witnesses are internal to this module - an internal type conforming to a public protocol keeps internal
 witnesses; only ActionUIDiff.register() is public. The rendering component is the DiffView product
 (module DiffView), which ActionUIChat also consumes for its tool-card diffs.
 */

import SwiftUI
import ActionUI
import DiffView

struct Diff: ActionUIViewConstruction {

    // Display-only element: no observable runtime value.
    static var valueType: Any.Type = Void.self

    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validated = properties

        for key in ["oldText", "newText", "oldFile", "newFile"] {
            if let value = validated[key], !(value is String) {
                logger.log("Diff \(key) must be a String; ignoring", .warning)
                validated[key] = nil
            }
        }

        for key in ["contextLines", "maxRenderedLines"] {
            if let value = validated[key], !(value is Int) {
                logger.log("Diff \(key) must be an integer; ignoring", .warning)
                validated[key] = nil
            }
        }

        return validated
    }

    // STATELESS: resolve both sides from the passed properties and build the view fresh every
    // invocation. Capturing nothing is what makes a post-display setElementProperty re-render live.
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let oldInput = resolveInput(text: properties["oldText"], file: properties["oldFile"], side: "old", logger: logger)
        let newInput = resolveInput(text: properties["newText"], file: properties["newFile"], side: "new", logger: logger)

        // A file we could not read becomes an honest note listing the offending path(s), not a diff
        // against an empty side (which would misleadingly look like a full deletion / addition).
        var unreadablePaths: [String] = []
        if case .unreadable(let path) = oldInput {
            unreadablePaths.append(path)
        }
        if case .unreadable(let path) = newInput {
            unreadablePaths.append(path)
        }
        guard unreadablePaths.isEmpty,
              case .text(let oldText) = oldInput,
              case .text(let newText) = newInput else {
            return unreadableNote(paths: unreadablePaths)
        }

        let contextLines = intProperty(properties, key: "contextLines", default: 3, minimum: 0, logger: logger)
        let maxRenderedLines = intProperty(properties, key: "maxRenderedLines", default: 300, minimum: 1, logger: logger)
        return DiffView(oldText: oldText, newText: newText,
                        contextLines: contextLines, maxRenderedLines: maxRenderedLines)
    }

    // Baseline View modifiers (frame, padding, background, ...) are applied by the registry.
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    // Void-value element (display-only): initial value / states pass through from the model.
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }

    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil

    // Leaf view: no child containers accept runtime insertions.
    static var insertableContainers: [String: ContainerShape]? = nil

    // MARK: - Input resolution

    /// One side's resolved text, or a path the wrapper could not read. Kept separate from rendering
    /// (a small value, no SwiftUI) so the resolution rules are unit-testable without building a view.
    enum ResolvedInput: Equatable {
        case text(String)
        case unreadable(path: String)
    }

    /// Resolves one side of the diff from its text and file properties.
    /// - text wins over file: if `text` is a string it is used (warning if `file` is also set).
    /// - otherwise `file` is tilde-expanded and read as UTF-8; missing, over 4 MB, or non-UTF-8
    ///   yields `.unreadable`.
    /// - neither given yields `.text("")` (a legitimate empty side: pure addition / removal).
    static func resolveInput(text: Any?, file: Any?, side: String, logger: any ActionUILogger) -> ResolvedInput {
        if let text = text as? String {
            if file is String {
                logger.log("Diff \(side): both text and file set; using text", .warning)
            }
            return .text(text)
        }

        guard let path = file as? String else {
            return .text("")
        }

        let expanded = (path as NSString).expandingTildeInPath
        let fileManager = FileManager.default

        guard let attributes = try? fileManager.attributesOfItem(atPath: expanded),
              let size = attributes[.size] as? Int, size <= 4_194_304 else {
            logger.log("Diff \(side): cannot read '\(expanded)' (missing or over 4 MB); rendering a note", .warning)
            return .unreadable(path: expanded)
        }

        guard let data = fileManager.contents(atPath: expanded),
              let contents = String(data: data, encoding: .utf8) else {
            logger.log("Diff \(side): '\(expanded)' is not readable UTF-8; rendering a note", .warning)
            return .unreadable(path: expanded)
        }

        return .text(contents)
    }

    /// Reads an integer property, falling back to `defaultValue` (with a warning) when it is
    /// ill-typed or below `minimum`. validateProperties already drops non-integers; the range
    /// check lives here.
    private static func intProperty(_ properties: [String: Any], key: String,
                                    default defaultValue: Int, minimum: Int,
                                    logger: any ActionUILogger) -> Int {
        guard let raw = properties[key] else {
            return defaultValue
        }
        guard let value = raw as? Int else {
            logger.log("Diff \(key) must be an integer; using \(defaultValue)", .warning)
            return defaultValue
        }
        guard value >= minimum else {
            logger.log("Diff \(key) must be >= \(minimum); using \(defaultValue)", .warning)
            return defaultValue
        }
        return value
    }

    /// A small secondary-styled note naming the file path(s) the wrapper could not read.
    private static func unreadableNote(paths: [String]) -> some SwiftUI.View {
        SwiftUI.VStack(alignment: .leading, spacing: 2) {
            ForEach(paths, id: \.self) { path in
                SwiftUI.Text("Cannot read \(path)")
            }
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
    }
}
