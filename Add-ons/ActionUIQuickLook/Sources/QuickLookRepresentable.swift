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

/// QLPreviewView's in-process text renderer installs a non-selectable NSTextView (QLTextView) for
/// plain-text / source / JSON files, so a preview that is selectable in Finder and qlmanage comes up
/// non-selectable when embedded here. There is no public switch for this, and the Finder-side
/// `QLEnableTextSelection` default has no effect in-process, so we flip the inner NSTextView
/// ourselves: after each load we walk the subtree and set `isSelectable = true` on any NSTextView.
/// The text view is built asynchronously, and rebuilt (back to non-selectable) on every source
/// change, so a short bounded poll re-applies after refreshPreviewItem(); layout() covers later
/// relayouts. Web (Markdown/HTML), PDF, and image previews use their own already-selectable views
/// and are left untouched - the NSTextView cast simply doesn't match them.
final class SelectableQLPreviewView: QLPreviewView {
    private var pollsLeft = 0

    /// Begin (re)enforcing selectable text. Call right after refreshPreviewItem(); the poll bridges
    /// the async build of the inner text view. Re-entrant: refreshes the window without stacking
    /// concurrent poll chains.
    func enforceSelectableText() {
        let alreadyPolling = pollsLeft > 0
        pollsLeft = 12              // ~1.4s window at 120ms steps
        if !alreadyPolling {
            pollSelectable()
        }
    }

    private func pollSelectable() {
        guard pollsLeft > 0 else {
        	return
        }
        pollsLeft -= 1
        makeTextSelectable(in: self)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
        	self?.pollSelectable()
        }
    }

    private func makeTextSelectable(in view: NSView) {
        if let textView = view as? NSTextView, !textView.isSelectable {
            textView.isSelectable = true
        }
        for subview in view.subviews {
            makeTextSelectable(in: subview)
        }
    }

    override func layout() {
        super.layout()
        makeTextSelectable(in: self)
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
            view.enforceSelectableText()
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
