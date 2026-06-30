// Add-ons/ActionUIChat/Sources/ChatRootView.swift
//
// The SwiftUI surface for one `Chat` element: a transcript above a composer.
//
// Owns the @StateObject ChatStore (so the store's lifetime follows the view's
// identity), starts the session on appear, and tears it down on disappear. M1
// renders the single-alignment transcript (every message leading / full-width,
// parties distinguished by tint + role label) and a composer whose submit policy
// is config-driven. Dual alignment, Markdown rendering, and the agentic side
// surfaces arrive in later milestones; this view stays the same shape.

import SwiftUI
import ActionUI

struct ChatRootView: View {

    @StateObject private var store: ChatStore
    private let config: ChatConfig

    private let bottomAnchor = "chat.bottom.anchor"

    init(config: ChatConfig, windowUUID: String, elementID: Int, logger: any ActionUILogger) {
        self.config = config
        _store = StateObject(wrappedValue: ChatStore(config: config, windowUUID: windowUUID,
                                                     elementID: elementID, logger: logger))
    }

    var body: some View {
        VStack(spacing: 0) {
            transcript
            Divider()
            composer
        }
        .onAppear { store.start() }
        .onDisappear { store.teardown() }
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(store.items) { item in
                        row(for: item).id(item.id)
                    }
                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: store.items) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func row(for item: ChatItem) -> some View {
        switch item {
        case .message(let message):
            MessageRow(message: message, config: config)
        case .system(_, let text):
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        case .error(_, let text):
            Label(text, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Composer

    @ViewBuilder
    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            inputField
            if store.isStreaming {
                Button(role: .destructive) { store.stop() } label: {
                    Image(systemName: "stop.circle.fill").imageScale(.large)
                }
                .help("Stop")
                .keyboardShortcut(".", modifiers: .command)
            } else {
                sendButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .buttonStyle(.borderless)
        .disabled(!config.inputEnabled)
    }

    @ViewBuilder
    private var sendButton: some View {
        let button = Button { store.submitDraft() } label: {
            Image(systemName: "arrow.up.circle.fill").imageScale(.large)
        }
        .help("Send")
        .disabled(store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        // modifier-return: the multiline editor consumes plain Return (newline), so the Send button
        // submits on Cmd+Return. return / shift-return-newline: the single-line field's onSubmit
        // already handles Return, so the button takes no Return shortcut (which would double-submit).
        if config.submitOn == .modifierReturn {
            button.keyboardShortcut(.return, modifiers: .command)
        } else {
            button
        }
    }

    @ViewBuilder
    private var inputField: some View {
        if config.submitOn == .modifierReturn {
            multilineField
        } else {
            // Single-line composer: Return submits via onSubmit.
            TextField(config.placeholder, text: $store.draft)
                .textFieldStyle(.plain)
                .onSubmit { store.submitDraft() }
        }
    }

    // Multiline composer: a TextEditor, so plain Return inserts a newline (its natural behavior on
    // macOS and iOS) and Cmd+Return (the Send button's shortcut) submits. A TextField(axis: .vertical)
    // is deliberately NOT used here: on macOS its Return commits and selects the text instead of
    // inserting a newline. TextEditor has no placeholder, so an overlaid Text stands in when empty.
    private var multilineField: some View {
        ZStack(alignment: .topLeading) {
            if store.draft.isEmpty {
                Text(config.placeholder)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $store.draft)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 22, maxHeight: 120)
        }
    }
}

// MARK: - Message row (single alignment)

private struct MessageRow: View {
    let message: ChatMessage
    let config: ChatConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if config.showRoleLabels {
                let label = config.style(for: message.role).label
                if !label.isEmpty {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                }
            }
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Message text is rendered as Markdown (M2). A streaming row re-parses on each coalesced
    // flush, with an open code fence balanced so it never swallows the buffer; finalized rows
    // parse once. A streaming row with no text yet shows an ellipsis so the bubble has height.
    @ViewBuilder private var content: some View {
        if message.text.isEmpty && message.isStreaming {
            Text("\u{2026}").foregroundStyle(.secondary)
        } else {
            MarkdownView(text: message.text, isStreaming: message.isStreaming)
        }
    }

    private var tint: Color {
        ChatTint.color(for: config.style(for: message.role).tint)
    }
}

// MARK: - Tint token resolver

// ActionUI's ColorHelper is internal, so the add-on resolves the common color
// tokens locally for M1 (the same token vocabulary). Promoting a public color
// resolver in core would let this defer to the framework; tracked as a later
// refinement.
private enum ChatTint {
    static func color(for token: String) -> Color {
        switch token.lowercased() {
        case "accent":              return .accentColor
        case "primary":             return .primary
        case "secondary", "tertiary": return .secondary
        case "red":                 return .red
        case "orange":              return .orange
        case "yellow":              return .yellow
        case "green":               return .green
        case "mint":                return .mint
        case "teal":                return .teal
        case "blue":                return .blue
        case "indigo":              return .indigo
        case "purple":              return .purple
        case "pink":                return .pink
        case "gray", "grey":        return .gray
        default:                    return .secondary
        }
    }
}
