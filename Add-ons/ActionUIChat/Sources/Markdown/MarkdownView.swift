// Add-ons/ActionUIChat/Sources/Markdown/MarkdownView.swift
//
// Renders a chat message's Markdown as a SINGLE native text view, so the whole message is selectable
// and copyable as one unit. (An earlier version rendered each block as a separate SwiftUI view, which
// looked right but broke selection - SwiftUI text selection cannot span sibling views, so a table
// selected per cell and a list per line.) The pipeline: parse the buffer -> build one NSAttributedString
// (MarkdownAttributed) -> show it in a self-sizing NSTextView / UITextView (MessageTextView).
//
// Streaming: a streaming message is re-parsed and rebuilt on each coalesced flush. The only structurally
// destructive incomplete state is an open code fence (it would otherwise swallow the rest of the buffer),
// so streaming text is passed through `MarkdownStreaming.balanceOpenFence` first - the design's "render
// the open fence as a code block immediately". Unterminated inline spans need no special case (the parser
// renders a half-typed `**bold` as literal text until it closes). Only the streaming row re-parses;
// finalized rows are immutable.

import SwiftUI

struct MarkdownView: View {
    let text: String
    var isStreaming: Bool = false

    var body: some View {
        let source = isStreaming ? MarkdownStreaming.balanceOpenFence(text) : text
        let attributed = MarkdownAttributed.attributedString(from: MarkdownParser.parse(source))
        MessageTextView(attributed: attributed)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Streaming fence balancing

enum MarkdownStreaming {
    /// If the buffer has an unterminated code fence (the opening ``` / ~~~ has no matching close yet),
    /// append a synthetic closing fence so the open block renders as a growing code block instead of
    /// swallowing the remaining text. No-op when fences are balanced.
    static func balanceOpenFence(_ text: String) -> String {
        var open = false
        var fenceChar: Character = "`"
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            let opensBacktick = t.hasPrefix("```")
            let opensTilde = t.hasPrefix("~~~")
            if !open, opensBacktick || opensTilde {
                open = true
                fenceChar = opensBacktick ? "`" : "~"
            } else if open, !t.isEmpty, t.allSatisfy({ $0 == fenceChar }), t.count >= 3 {
                open = false
            }
        }
        if open {
            return text + "\n" + String(repeating: fenceChar, count: 3)
        }
        return text
    }
}
