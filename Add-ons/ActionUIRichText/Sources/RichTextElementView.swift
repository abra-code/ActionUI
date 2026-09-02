// Add-ons/ActionUIRichText/Sources/RichTextElementView.swift
//
// The element's SwiftUI body: the package's RichText view plus the find layers the JSON asked for. The
// package splits find into an engine, a draw-only highlight modifier and a bar; this view maps the
// element's two knobs onto them - the "showFindBar" property shows the bar and its shortcuts, states["search"]
// drives the query from the host - and keeps everything else out of the way:
//   - the Markdown is rendered ONCE per (source, theme): the find controller publishes on every keystroke,
//     which re-runs this body, and re-parsing the document each time would be pure waste;
//   - the wrapper is rebuilt by ActionUI on every model change (ActionUIView observes the whole view
//     model), but it is cheap to rebuild and its stored properties compare equal, so SwiftUI skips its
//     body unless the Markdown, the theme or the find controller actually changed; the search key is
//     read through the states publisher so its value is applied once per change, not per body pass.

import SwiftUI
import Combine
import ActionUI
import RichText

struct RichTextElementView: View {
    let model: ViewModel
    let markdown: String
    let theme: RichTextTheme
    let behavior: RichTextWidthBehavior
    let showsFindBar: Bool
    let logger: any ActionUILogger

    @StateObject private var find = RichTextFindController()
    // Reference-in-@State: the cache mutates without being a state change, so a render does not itself
    // trigger a re-render.
    @State private var cache = RenderCache()
    // The last states["search"] value applied, so the channel re-delivering it on every states change
    // does not re-open a bar the reader closed; and the last value refused, so a host's mistake is
    // said once rather than once per states change.
    @State private var lastAppliedSearch: String?
    @State private var lastRejectedSearch: String?

    var body: some View {
        let document = cache.view(markdown: markdown, theme: theme).widthBehavior(behavior).find(find)
        Group {
            if showsFindBar {
                document.richTextFindBar(find)
            } else {
                document
            }
        }
        // The publisher replays its current value to a new subscriber, which would run applySearch
        // inside the view update that installs this view; the first value is taken in onAppear instead.
        .onAppear {
            applySearch(model.states["search"])
        }
        .onReceive(model.$states.dropFirst()) { states in
            applySearch(states["search"])
        }
    }

    private func applySearch(_ value: Any?) {
        // nil: the key was never set - no opinion.
        guard let value else {
            return
        }
        guard let query = value as? String else {
            let description = String(describing: value)
            if description != lastRejectedSearch {
                lastRejectedSearch = description
                logger.log("RichText search state must be a String; ignoring", .warning)
            }
            return
        }
        guard query != lastAppliedSearch else {
            return
        }
        lastAppliedSearch = query
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if find.isPresented || !find.query.isEmpty {
                find.dismiss()
            }
            return
        }
        find.query = query
        if showsFindBar {
            // Without focus: the reader is typing in the host's field, which is what sent this.
            find.present(focus: false)
        }
    }
}

/// One rendered RichText view per (Markdown, theme), reused until either changes.
@MainActor
private final class RenderCache {
    private var key: (markdown: String, theme: RichTextTheme)?
    private var rendered: RichText?

    func view(markdown: String, theme: RichTextTheme) -> RichText {
        if let key, let rendered, key.markdown == markdown, key.theme == theme {
            return rendered
        }
        // Unqualified `RichText` is the imported package view (the element type is RichTextView, so
        // nothing local shadows it). Module-qualifying as `RichText.RichText` does NOT work: `import
        // RichText` brings the type `RichText` into scope, which shadows the module name of the same name.
        let view = RichText(markdown: markdown, theme: theme)
        key = (markdown, theme)
        rendered = view
        return view
    }
}
