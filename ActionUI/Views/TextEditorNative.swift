// Views/TextEditorNative.swift
//
// The native TextEditor on macOS ("implementation": "native"): an NSTextView in an NSScrollView.
//
// SwiftUI's TextEditor lays its whole text out again on every change of its text, so text that
// grows by appending costs the whole text each time: about 0.5 ms per KB of the whole text on
// macOS 27, which blocks the main thread for seconds once a log reaches megabytes. This editor
// compares a new value with the text it shows; a value that extends it (appendElementText, or a
// setElementValue whose value starts with the text shown) is appended to the text storage, so only
// the new text is laid out. Any other value replaces the text.
//
// Plain text only: TextEditor+SwiftUI.swift picks this view only without "markdown". The font and
// text color come from the element's own "font" and "foregroundStyle" properties, since an
// AppKit view cannot read a SwiftUI font or style from the environment on the package's baseline.

#if os(macOS)
import SwiftUI
import AppKit

extension TextEditor {
    /// Reads the model's value (so it renders again when the value changes) and shows it in the
    /// native text view, with the placeholder over an empty editor.
    struct NativeTextEditorContainer: SwiftUI.View {
        let model: ViewModel
        let initialValue: String
        let isReadOnly: Bool
        let placeholder: String?
        let valueChangeActionID: String?
        let windowUUID: String
        let elementId: Int
        let style: NativeTextStyle

        var body: some SwiftUI.View {
            let text = model.value as? String ?? initialValue
            let editor = NativeTextView(text: text, isReadOnly: isReadOnly, style: style) { [model, valueChangeActionID, elementId, windowUUID] newValue in
                TextField.userEditedText(newValue, valueChangeActionID: valueChangeActionID, viewID: elementId,
                                         model: model, windowUUID: windowUUID)
            }
            if let placeholder, !placeholder.isEmpty {
                editor.overlay(
                    SwiftUI.Group {
                        if text.isEmpty {
                            SwiftUI.Text(placeholder)
                                .font(SwiftUI.Font(style.font as CTFont))
                                .foregroundColor(.gray)
                                .padding(.leading, NativeTextView.lineFragmentPadding)
                                .allowsHitTesting(false)
                        } else {
                            SwiftUI.EmptyView()
                        }
                    },
                    alignment: .topLeading
                )
            } else {
                editor
            }
        }
    }

    /// The font, text color and background of the native editor, from the element's properties.
    struct NativeTextStyle: Equatable {
        var font: NSFont
        var textColor: NSColor
        /// False with "scrollContentBackground": "hidden": the views behind the editor show through.
        var drawsBackground: Bool

        @MainActor
        init(_ properties: [String: Any], logger: any ActionUILogger) {
            if let fontProperty = properties["font"], fontProperty is String || fontProperty is [String: Any] {
                font = FontHelper.nsFont(for: FontSpec.parse(fontProperty, logger: logger))
            } else {
                font = NSFont.preferredFont(forTextStyle: .body)
            }
            let color = (properties["foregroundStyle"] as? String).flatMap(ColorHelper.resolveColor)
            textColor = color.map { NSColor($0) } ?? .textColor
            drawsBackground = properties["scrollContentBackground"] as? String != "hidden"
        }

        var attributes: [NSAttributedString.Key: Any] {
            [.font: font, .foregroundColor: textColor]
        }
    }

    struct NativeTextView: NSViewRepresentable {
        /// NSTextContainer's default: the text starts this far from the editor's leading edge.
        static let lineFragmentPadding: CGFloat = 5

        let text: String
        let isReadOnly: Bool
        let style: NativeTextStyle
        let onEdit: (String) -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        func makeNSView(context: Context) -> NSScrollView {
            let scrollView = NSTextView.scrollableTextView()
            scrollView.borderType = .noBorder
            scrollView.hasVerticalScroller = true
            scrollView.autohidesScrollers = true
            let textView = scrollView.documentView as! NSTextView
            textView.isRichText = false
            textView.importsGraphics = false
            textView.usesFindBar = true
            textView.isIncrementalSearchingEnabled = true
            textView.textContainer?.lineFragmentPadding = Self.lineFragmentPadding
            textView.delegate = context.coordinator
            context.coordinator.textView = textView
            context.coordinator.onEdit = onEdit
            context.coordinator.apply(style, to: textView, scrollView: scrollView)
            context.coordinator.show(text, in: textView)
            update(textView, context: context)
            return scrollView
        }

        func updateNSView(_ scrollView: NSScrollView, context: Context) {
            guard let textView = scrollView.documentView as? NSTextView else { return }
            context.coordinator.onEdit = onEdit
            context.coordinator.apply(style, to: textView, scrollView: scrollView)
            context.coordinator.show(text, in: textView)
            update(textView, context: context)
        }

        /// Read-only: selectable, not editable. Disabled ("disabled", or an enclosing view's): neither.
        private func update(_ textView: NSTextView, context: Context) {
            let isEnabled = context.environment.isEnabled
            textView.isEditable = isEnabled && !isReadOnly
            textView.isSelectable = isEnabled
            textView.allowsUndo = textView.isEditable
        }

        @MainActor
        final class Coordinator: NSObject, NSTextViewDelegate {
            /// The text the text view shows, as last shown or typed; native UTF-8, so comparing a
            /// new value with it is a byte comparison.
            private(set) var shown = ""
            private var style: NativeTextStyle?
            var onEdit: ((String) -> Void)?
            /// The editor's own undo: a change the host makes clears it, so Undo never applies an
            /// edit to text that changed under it, and the window's other views keep theirs.
            private let undoManager = UndoManager()
            /// The text view whose Undo and Redo are reported as edits.
            weak var textView: NSTextView?

            override init() {
                super.init()
                // Undo and Redo change the text without textDidChange (measured on macOS 27), so the
                // value would keep the undone text.
                for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
                    NotificationCenter.default.addObserver(self, selector: #selector(undoManagerDidChangeText(_:)),
                                                           name: name, object: undoManager)
                }
            }

            @objc private func undoManagerDidChangeText(_ notification: Notification) {
                guard let textView else { return }
                userChangedText(in: textView)
            }

            func apply(_ newStyle: NativeTextStyle, to textView: NSTextView, scrollView: NSScrollView) {
                guard newStyle != style else { return }
                style = newStyle
                textView.font = newStyle.font
                textView.textColor = newStyle.textColor
                textView.typingAttributes = newStyle.attributes
                textView.drawsBackground = newStyle.drawsBackground
                scrollView.drawsBackground = newStyle.drawsBackground
            }

            /// Shows `text`: appends what follows the text shown when `text` starts with it, else
            /// replaces the text. Nothing when it is the text shown.
            func show(_ text: String, in textView: NSTextView) {
                let shownCount = shown.utf8.count
                let textCount = text.utf8.count
                let extendsShown = textCount >= shownCount && Self.utf8(of: text, startsWith: shown)
                if extendsShown && textCount == shownCount {
                    return
                }
                guard let storage = textView.textStorage else { return }
                if extendsShown {
                    // `shown` is a whole String, so its end is a Unicode scalar boundary in `text`
                    let start = text.utf8.index(text.utf8.startIndex, offsetBy: shownCount)
                    let piece = String(text.unicodeScalars[start...])
                    storage.append(NSAttributedString(string: piece, attributes: style?.attributes ?? [:]))
                } else {
                    storage.setAttributedString(NSAttributedString(string: text, attributes: style?.attributes ?? [:]))
                }
                var native = text
                native.makeContiguousUTF8()
                shown = native
                undoManager.removeAllActions()
            }

            /// Whether the UTF-8 of `text` starts with that of `prefix`, compared with memcmp: it runs
            /// on every change of a text that may be megabytes.
            private static func utf8(of text: String, startsWith prefix: String) -> Bool {
                var text = text
                var prefix = prefix
                return text.withUTF8 { textBytes in
                    prefix.withUTF8 { prefixBytes in
                        guard prefixBytes.count <= textBytes.count else { return false }
                        guard let textBase = textBytes.baseAddress, let prefixBase = prefixBytes.baseAddress else { return true }
                        return memcmp(textBase, prefixBase, prefixBytes.count) == 0
                    }
                }
            }

            func textDidChange(_ notification: Notification) {
                guard let textView = notification.object as? NSTextView else { return }
                userChangedText(in: textView)
            }

            /// The user changed the text (typing, Undo, Redo): it is the text shown and the value.
            private func userChangedText(in textView: NSTextView) {
                var text = textView.string
                text.makeContiguousUTF8()
                shown = text
                onEdit?(text)
            }

            func undoManager(for view: NSTextView) -> UndoManager? {
                undoManager
            }
        }
    }
}
#endif
