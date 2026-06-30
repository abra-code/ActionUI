// Add-ons/ActionUIQuickLook/Sources/QuickLookRepresentable.swift
//
// SwiftUI wrapper around Apple's in-process Quick Look UI:
//   - macOS:          QLPreviewView          (NSViewRepresentable)
//   - iOS / visionOS: QLPreviewController     (UIViewControllerRepresentable, inline child)
//
// Mirrors ActionUI's WebViewNative representable: an @ObservedObject ViewModel drives runtime
// updates (ActionUIView re-renders on model.value changes -> updateNSView/updateUIViewController),
// and a Coordinator tracks the last-applied source to avoid redundant reloads and fires
// valueChangeActionID through ActionUIModel.shared.actionHandler.

import SwiftUI
import ActionUI

#if os(macOS)
import Quartz            // QLPreviewView (QuickLookUI, re-exported by the Quartz umbrella)
import AppKit            // NSWorkspace for "open in default app"
#elseif os(iOS) || os(visionOS)
import QuickLook         // QLPreviewController
#endif

@MainActor
struct QLPreviewRepresentable {
    @ObservedObject var model: ViewModel
    let properties: [String: Any]
    let element: any ActionUIElementBase
    let windowUUID: String
    let logger: any ActionUILogger

    /// Effective source: the runtime value wins, else the filePath JSON seed.
    var sourceString: String? {
        if let value = model.value as? String, !value.isEmpty { return value }
        if let path = properties["filePath"] as? String, !path.isEmpty { return path }
        return nil
    }

    var valueChangeActionID: String? { properties["valueChangeActionID"] as? String }

    /// When true, show preview chrome: iOS wraps the controller in a UINavigationController (title +
    /// share/actions); macOS shows a header bar (file name + share / open) via QuickLookMacView.
    /// Default false (a chrome-light embedded pane).
    var showsChrome: Bool { properties["showsChrome"] as? Bool ?? false }

    /// Resolves a path or "file://" string to a file URL.
    static func fileURL(from source: String) -> URL? {
        source.hasPrefix("file://") ? URL(string: source) : URL(fileURLWithPath: source)
    }

    func makeQLCoordinator() -> Coordinator {
        Coordinator(valueChangeActionID: valueChangeActionID, windowUUID: windowUUID, viewID: element.id)
    }
}

// MARK: - Coordinator (shared)

extension QLPreviewRepresentable {
    @MainActor
    final class Coordinator: NSObject {
        var lastSource: String?
        var currentURL: URL?
        let valueChangeActionID: String?
        let windowUUID: String
        let viewID: Int
        #if os(iOS) || os(visionOS)
        weak var preview: QLPreviewController?
        #endif

        init(valueChangeActionID: String?, windowUUID: String, viewID: Int) {
            self.valueChangeActionID = valueChangeActionID
            self.windowUUID = windowUUID
            self.viewID = viewID
        }

        /// Fires the host-facing change notification after a new source is applied.
        func fireValueChange() {
            guard let actionID = valueChangeActionID else { return }
            ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: viewID, viewPartID: 0)
        }
    }
}

// MARK: - macOS backing (QLPreviewView)

#if os(macOS)

/// Makes an embedded Quick Look text preview behave like Finder's: selectable, and actually
/// drag-selectable. Two separate things are wrong by default when QLPreviewView is hosted inside a
/// SwiftUI hierarchy, and this subclass fixes both.
///
/// 1. The text comes up non-selectable. QLPreviewView's in-process renderer installs its NSTextView
///    (QLTextView) with `isSelectable = false`, and there is no public switch for it (the
///    Finder-side `QLEnableTextSelection` default has no effect in-process). We flip `isSelectable`
///    ourselves once the text view appears. It is built asynchronously after refreshPreviewItem()
///    with no load-completion callback - not present synchronously, nor after a forced layout, only
///    a few hundred ms later - so a Timer applies it once the load settles. The timer is added in
///    `.default` mode (not `.common`) so it is paused during the `.eventTracking` run-loop mode and
///    cannot fire while the user is mid-drag. Web/PDF/image previews have no NSTextView and are left
///    untouched.
///
/// 2. Drag-select silently fails and clicks lag. SwiftUI attaches its own gesture recognizers - a
///    pan and a click - to every embedded NSViewRepresentable, both with
///    `delaysPrimaryMouseButtonEvents = true`. That buffers the mouse-down/drag while the pan
///    recognizer decides whether it owns the gesture, so primary mouse events reach the QLTextView
///    late and batched: clicks are slow, and a drag never gets the real-time event stream its
///    selection-tracking loop needs, so click-drag selection does nothing. (A plain AppKit window -
///    e.g. a standalone preview window - has no such recognizers, so it never had this problem;
///    that is why the same code selected fine there but not when embedded.) We clear the delay on
///    each recognizer as SwiftUI attaches it, so mouse events reach the text view immediately.
final class SelectableQLPreviewView: QLPreviewView {
    private var selectionTimer: Timer?
    private var selectionTicks = 0

    /// Clears `delaysPrimaryMouseButtonEvents` on the pan/click recognizers SwiftUI installs on this
    /// view, at the moment each is attached, so primary mouse events are not buffered before reaching
    /// the inner text view. This is what restores click-drag text selection inside a SwiftUI host.
    override func addGestureRecognizer(_ gestureRecognizer: NSGestureRecognizer) {
        gestureRecognizer.delaysPrimaryMouseButtonEvents = false
        super.addGestureRecognizer(gestureRecognizer)
    }

    /// Make the renderer's text view selectable once the preview finishes loading. Call right after
    /// refreshPreviewItem(). Retries until the text view appears (it loads asynchronously), then
    /// stops. Restarts cleanly on a source change - the previous timer is invalidated first.
    /// Target-action (rather than a closure) so the tick is a normal main-actor method, and so the
    /// timer's brief retain of self is released the moment it invalidates.
    func enableTextSelection() {
        selectionTimer?.invalidate()
        selectionTicks = 0
        let timer = Timer(timeInterval: 0.1, target: self, selector: #selector(selectionTick(_:)),
                          userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .default)
        selectionTimer = timer
    }

    @objc private func selectionTick(_ timer: Timer) {
        selectionTicks += 1
        if makeTextSelectable(in: self) || selectionTicks >= 20 {   // ~2s safety cap
            timer.invalidate()
        }
    }

    /// Flips the first NSTextView found to selectable; returns true once one is found (a text preview
    /// has a single text view). Stops at the text view rather than descending into its TextKit
    /// subtree.
    @discardableResult
    private func makeTextSelectable(in view: NSView) -> Bool {
        if let textView = view as? NSTextView {
            textView.isSelectable = true
            return true
        }
        for subview in view.subviews {
            if makeTextSelectable(in: subview) {
                return true
            }
        }
        return false
    }
}

extension QLPreviewRepresentable: NSViewRepresentable {

    func makeCoordinator() -> Coordinator { makeQLCoordinator() }

    func makeNSView(context: Context) -> SelectableQLPreviewView {
        let style: QLPreviewViewStyle = (properties["previewStyle"] as? String == "compact") ? .compact : .normal
        let view = SelectableQLPreviewView(frame: .zero, style: style) ?? SelectableQLPreviewView()
        apply(to: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: SelectableQLPreviewView, context: Context) {
        apply(to: view, coordinator: context.coordinator)
    }

    private func apply(to view: SelectableQLPreviewView, coordinator: Coordinator) {
        let source = sourceString
        guard source != coordinator.lastSource else { return }
        coordinator.lastSource = source
        if let source, let url = Self.fileURL(from: source) {
            view.previewItem = url as NSURL
            view.refreshPreviewItem()
            view.enableTextSelection()
        } else {
            view.previewItem = nil
        }
        coordinator.fireValueChange()
    }
}

/// macOS chrome wrapper. With showsChrome, puts a thin header (file name + Share + Open-in-default-
/// app) above the QLPreviewView, mirroring the iOS nav bar; otherwise it is just the preview.
/// QLPreviewView has no built-in toolbar, so the chrome is composed here in SwiftUI.
@MainActor
struct QuickLookMacView: View {
    @ObservedObject var model: ViewModel
    let properties: [String: Any]
    let element: any ActionUIElementBase
    let windowUUID: String
    let logger: any ActionUILogger

    private var showsChrome: Bool { properties["showsChrome"] as? Bool ?? false }

    private var sourceURL: URL? {
        let path = (model.value as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (properties["filePath"] as? String)
        return path.flatMap { QLPreviewRepresentable.fileURL(from: $0) }
    }

    private var preview: QLPreviewRepresentable {
        QLPreviewRepresentable(model: model, properties: properties, element: element,
                               windowUUID: windowUUID, logger: logger)
    }

    var body: some View {
        if showsChrome {
            VStack(spacing: 0) {
                header
                Divider()
                preview
            }
        } else {
            preview
        }
    }

    @ViewBuilder private var header: some View {
        HStack(spacing: 12) {
            Text(sourceURL?.lastPathComponent ?? "No file")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let url = sourceURL {
                // Both controls carry an Image label at the same .imageScale(.medium), so they render
                // at the same size and line up. The Share stays a ShareLink (the only no-AppKit way to
                // share), but with an Image label like the Open Button rather than its default label.
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up").imageScale(.medium)
                }
                .help("Share")
                Button { NSWorkspace.shared.open(url) } label: {
                    Image(systemName: "arrow.up.forward").imageScale(.medium)
                }
                .help("Open in default app")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .buttonStyle(.borderless)
    }
}
#endif

// MARK: - iOS / visionOS backing (QLPreviewController)

#if os(iOS) || os(visionOS)
extension QLPreviewRepresentable: UIViewControllerRepresentable {

    func makeCoordinator() -> Coordinator { makeQLCoordinator() }

    func makeUIViewController(context: Context) -> UIViewController {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        preview.delegate = context.coordinator
        context.coordinator.preview = preview
        context.coordinator.applyCurrentSource(sourceString)
        // showsChrome: wrap the preview in a UINavigationController so QuickLook's nav bar (title +
        // share/actions) renders inline. Otherwise the bare controller is chrome-light.
        return showsChrome ? UINavigationController(rootViewController: preview) : preview
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        context.coordinator.applyCurrentSource(sourceString)
    }
}

extension QLPreviewRepresentable.Coordinator: QLPreviewControllerDataSource, QLPreviewControllerDelegate {

    func applyCurrentSource(_ source: String?) {
        guard source != lastSource else { return }
        lastSource = source
        currentURL = source.flatMap { QLPreviewRepresentable.fileURL(from: $0) }
        preview?.reloadData()
        fireValueChange()
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        currentURL == nil ? 0 : 1
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        // numberOfPreviewItems returns 0 when currentURL is nil, so this is only reached with a URL.
        (currentURL as NSURL?) ?? (URL(fileURLWithPath: "/dev/null") as NSURL)
    }
}
#endif
