// Add-ons/ActionUIChat/Sources/Core/ChatRootView.swift
//
// The SwiftUI surface for one `Chat` element: a transcript above a composer.
//
// Owns the @StateObject ChatStore (so the store's lifetime follows the view's
// identity), starts the session on appear, and tears it down on disappear. Renders
// the single-alignment transcript (every message leading / full-width, parties
// distinguished by tint + role label) and a composer whose submit policy is
// config-driven. Message bodies render as Markdown through the RichText component
// (M2). Agentic surfaces (M3) are transcript rows too: thoughts fold behind a
// disclosure, tool calls are status cards that mutate in place, and a pending
// permission request pins an approval card above the composer (an inline gate,
// not a window-modal sheet, so an embedded element never takes over the host
// window). Dual alignment and the M5 side panels arrive in later milestones;
// this view stays the same shape.

import SwiftUI
import ActionUI
import RichText
import DiffView
import AsyncImageCache

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
            if !store.plan.isEmpty && config.surfaces.plan != .hidden {
                PlanPanel(entries: store.plan, initiallyExpanded: config.surfaces.plan != .collapsed)
                Divider()
            }
            transcript
            if let request = store.pendingPermissions.first {
                Divider()
                PermissionCard(request: request) { optionID in
                    store.respondToPermission(request.id, optionID: optionID)
                }
            }
            let commandMatches = SlashCommandMenu.matches(draft: store.draft, commands: store.availableCommands)
            if !commandMatches.isEmpty {
                Divider()
                SlashCommandMenuView(matches: commandMatches) { command in
                    store.draft = "/\(command.name) "
                }
            }
            Divider()
            composer
            if store.usage != nil || !store.configOptions.isEmpty {
                Divider()
                SessionStatusBar(usage: store.usage, options: store.configOptions) { optionID, value in
                    store.setConfigOption(optionID, value: value)
                }
            }
        }
        .onAppear { store.start() }
        .onDisappear { store.teardown() }
    }

    /// While an approval is pending, the composer input pauses (the Stop control stays live).
    private var permissionPending: Bool {
        !store.pendingPermissions.isEmpty
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
        case .thought(let thought):
            ThoughtRow(thought: thought, initiallyExpanded: config.surfaces.thoughts != .collapsed)
        case .toolCall(let call):
            ToolCallRow(call: call, compact: config.surfaces.toolCalls == .collapsed,
                        showsDiff: config.surfaces.diffs != .hidden)
        case .image(_, let role, let image):
            ImageRow(role: role, image: image, config: config)
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
        .disabled(store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || permissionPending)

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
                .disabled(permissionPending)
        } else {
            // Single-line composer: Return submits via onSubmit.
            TextField(config.placeholder, text: $store.draft)
                .textFieldStyle(.plain)
                .onSubmit { store.submitDraft() }
                .disabled(permissionPending)
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

    // Message text is rendered as Markdown by RichText: the shared cross-platform component lays
    // the whole message out in ONE selectable, self-sizing text view (headings, code, quotes, lists,
    // GFM tables, inline styling, links, inline images). A streaming row re-renders on each coalesced
    // flush; RichText's parser is streaming-safe (an unterminated span renders as literal text and
    // an open code fence renders as a growing code block), so no pre-balancing of the buffer is needed.
    // A streaming row with no text yet shows an ellipsis so the bubble has height.
    @ViewBuilder private var content: some View {
        if message.text.isEmpty && message.isStreaming {
            Text("\u{2026}").foregroundStyle(.secondary)
        } else {
            RichText(markdown: message.text)
        }
    }

    private var tint: Color {
        ChatTint.color(for: config.style(for: message.role).tint)
    }
}

// MARK: - Thought row (agentic reasoning)

// A streamed reasoning item, visually distinct from answer text: folded behind a small
// disclosure (per surfaces.thoughts; "collapsed" is the default), secondary styling.
// The label reads "Thinking..." while the thought streams and "Thoughts" once closed.
private struct ThoughtRow: View {
    let thought: ChatMessage
    @State private var expanded: Bool

    init(thought: ChatMessage, initiallyExpanded: Bool) {
        self.thought = thought
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Group {
                if thought.text.isEmpty && thought.isStreaming {
                    Text("\u{2026}").foregroundStyle(.secondary)
                } else {
                    RichText(markdown: thought.text).opacity(0.75)
                }
            }
            .padding(.top, 4)
        } label: {
            Label(thought.isStreaming ? "Thinking\u{2026}" : "Thoughts", systemImage: "brain")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Slash-command menu (agentic, M5)

/// The composer's slash-command menu model: active while the draft is a lone, partial
/// first token beginning with "/" (no whitespace typed yet) and an advertised command
/// name has that prefix. "/" alone lists everything. Internal (not private) so tests
/// can pin the matching.
enum SlashCommandMenu {
    static func matches(draft: String, commands: [SlashCommand]) -> [SlashCommand] {
        guard !commands.isEmpty, draft.hasPrefix("/") else {
            return []
        }
        let token = draft.dropFirst()
        guard !token.contains(where: \.isWhitespace) else {
            return []
        }
        let prefix = token.lowercased()
        return commands.filter { $0.name.lowercased().hasPrefix(prefix) }
    }
}

// The menu itself: pinned between the transcript and the composer while matches exist
// (mirroring the permission card's placement). Selection fills the draft with
// "/name " - the command still sends as ordinary prompt text. Tap-driven for now;
// keyboard navigation (arrows + Tab) is a later refinement.
private struct SlashCommandMenuView: View {
    let matches: [SlashCommand]
    let select: (SlashCommand) -> Void

    /// A menu, not a browser: only the top few matches show (typing narrows them).
    private static let visibleLimit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(matches.prefix(Self.visibleLimit)) { command in
                Button {
                    select(command)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("/\(command.name)")
                            .font(.system(.callout, design: .monospaced).weight(.medium))
                        Text(command.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
            }
            if matches.count > Self.visibleLimit {
                Text("\(matches.count - Self.visibleLimit) more\u{2026} keep typing to narrow")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Plan panel (agentic, M5)

// The agent's evolving task list (ACP `plan`), pinned ABOVE the transcript as a status
// surface - never interleaved with chat (surfaces.plan: panel default, expanded /
// collapsed, folded / hidden). The agent re-emits the whole plan as it works, so rows
// update in place; the label carries a completed-count summary for the folded state.
private struct PlanPanel: View {
    let entries: [PlanEntry]
    @State private var expanded: Bool

    init(entries: [PlanEntry], initiallyExpanded: Bool) {
        self.entries = entries
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(entries) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        statusIcon(entry.status)
                        Text(entry.content)
                            .font(.caption)
                            .strikethrough(entry.status == .completed)
                            .foregroundStyle(entry.status == .completed ? Color.secondary : Color.primary)
                    }
                }
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Plan (\(completedCount)/\(entries.count))", systemImage: "checklist")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var completedCount: Int {
        entries.filter { $0.status == .completed }.count
    }

    @ViewBuilder
    private func statusIcon(_ status: PlanEntry.Status) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .inProgress:
            ProgressView()
                .controlSize(.mini)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }
}

// MARK: - Session status bar (agentic, M5)

// A thin status line under the composer: the session's model / mode (from the agent's
// session-start config options) and token / cost usage when the agent reports it. An
// option with several choices is a menu - selecting sends .setConfigOption, and the
// display updates when the transport confirms (never optimistically, so a failed
// change needs no revert). Single-choice options render as plain text.
private struct SessionStatusBar: View {
    let usage: UsageInfo?
    let options: [SessionConfigOption]
    let select: (String, String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(options) { option in
                if option.options.count > 1 {
                    Menu {
                        ForEach(option.options, id: \.value) { choice in
                            Button {
                                select(option.id, choice.value)
                            } label: {
                                if choice.value == option.currentValue {
                                    Label(choice.name, systemImage: "checkmark")
                                } else {
                                    Text(choice.name)
                                }
                            }
                        }
                    } label: {
                        Text("\(option.name): \(option.currentChoiceName ?? option.currentValue)")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .fixedSize()
                } else {
                    Text("\(option.name): \(option.currentChoiceName ?? option.currentValue)")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            if let usage {
                Text(usageText(usage))
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func usageText(_ usage: UsageInfo) -> String {
        var parts: [String] = []
        if let size = usage.size, size > 0 {
            parts.append("\(Self.compact(usage.used)) / \(Self.compact(size)) tokens")
        } else {
            parts.append("\(Self.compact(usage.used)) tokens")
        }
        if let amount = usage.costAmount, amount > 0 {
            let currency = usage.costCurrency ?? ""
            if currency == "USD" {
                parts.append(String(format: "$%.4f", amount))
            } else {
                parts.append(String(format: "%.4f %@", amount, currency))
            }
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    private static func compact(_ value: Int) -> String {
        if value >= 1000 {
            return String(format: "%.1fk", Double(value) / 1000)
        }
        return "\(value)"
    }
}

/// Caps bulk tool detail for rendering: a tool call's content is often a whole file or
/// a long command output, and the card is a preview of the call, not a file viewer -
/// uncapped text would also make the transcript's attributed-string layout crawl.
/// Internal (not private) so tests can pin the behavior.
enum ToolDetailText {
    static let cap = 4000

    static func capped(_ text: String) -> String {
        guard text.count > cap else {
            return text
        }
        return text.prefix(cap) + "\n\u{2026} (truncated, \(text.count - cap) more characters)"
    }
}

// MARK: - Tool-call card (agentic)

// One tool invocation: a kind icon, the title, a status indicator, and - when the call
// carries content, a diff, or raw input / output - a disclosure with the detail. The
// card mutates in place as tool_call_update events arrive (same item id). The detail
// ALWAYS starts folded, whatever surfaces.toolCalls says: tool content is bulk material
// (a whole file read, a long command output), and auto-expanding it floods the
// transcript - the mainstream agentic UX shows the fact of the call, not its payload.
// "collapsed" additionally shrinks the card to a compact caption row (Thoughts-style).
// Expanded detail renders through ToolDetailText.capped so a megabyte read stays a
// preview. Diffs render through the standalone DiffView component (a line diff with hunks
// and old / new line-number gutters); surfaces.diffs "hidden" drops them from the card.
private struct ToolCallRow: View {
    let call: ToolCallModel
    let compact: Bool     // surfaces.toolCalls == .collapsed
    let showsDiff: Bool   // surfaces.diffs != .hidden
    @State private var expanded = false

    var body: some View {
        let column = VStack(alignment: .leading, spacing: 6) {
            header
            if expanded && hasDetail {
                detail
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        return Group {
            if compact {
                column
            } else {
                column
                    .padding(10)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.15)))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: kindIcon)
                .foregroundStyle(.secondary)
            Text(call.title)
                .font(compact ? .caption : .callout.weight(.medium))
                .foregroundStyle(compact ? Color.secondary : Color.primary)
                .lineLimit(compact ? 1 : 2)
            if hasDetail {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(expanded ? .degrees(90) : .zero)
            }
            Spacer(minLength: 8)
            status
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if hasDetail {
                withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if !call.contentText.isEmpty {
            RichText(markdown: ToolDetailText.capped(call.contentText))
        }
        if showsDiff, let diff = call.diff {
            Text(diff.path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            DiffView(oldText: diff.oldText ?? "", newText: diff.newText)
        }
        if let rawInput = call.rawInput {
            labeledCode("Input", ToolDetailText.capped(rawInput))
        }
        if let rawOutput = call.rawOutput {
            labeledCode("Output", ToolDetailText.capped(rawOutput))
        }
    }

    private var hasDetail: Bool {
        !call.contentText.isEmpty || (showsDiff && call.diff != nil) || call.rawInput != nil || call.rawOutput != nil
    }

    @ViewBuilder
    private func labeledCode(_ title: String, _ text: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
        codeBlock(text)
    }

    private func codeBlock(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private var kindIcon: String {
        switch call.kind {
        case .read:     return "doc.text"
        case .edit:     return "pencil"
        case .delete:   return "trash"
        case .move:     return "folder"
        case .search:   return "magnifyingglass"
        case .execute:  return "terminal"
        case .think:    return "brain"
        case .fetch:    return "network"
        case .other:    return "wrench.and.screwdriver"
        }
    }

    @ViewBuilder
    private var status: some View {
        switch call.status {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .inProgress:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Permission card (agentic approval gate)

// The head of the pending-permission queue, pinned between the transcript and the
// composer: the agent's question plus one button per agent-offered option (allow
// variants prominent, reject variants bordered). An inline gate rather than a
// window-modal sheet so an embedded Chat element never takes over the host window;
// the composer input pauses while a request is pending.
private struct PermissionCard: View {
    let request: PermissionRequest
    let respond: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(request.title, systemImage: "lock.shield")
                .font(.callout.weight(.medium))
            HStack(spacing: 8) {
                ForEach(request.options) { option in
                    if option.kind.allows {
                        Button(option.name) { respond(option.id) }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button(option.name, role: .destructive) { respond(option.id) }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08))
    }
}

// MARK: - Image row (single alignment)

// A standalone image element. Rendered with CachedImage (the AsyncImageCache view): bytes come from the
// shared memory + disk cache, decoded/scaled off the main thread; the box reserves the image's aspect up
// front (from the transport-provided pixelSize when known) so hydration does not reflow the transcript.
// The image is capped to a readable bubble width; maxPixelWidth bounds the decoded resolution to ~3x that.
private struct ImageRow: View {
    let role: ChatRole
    let image: ChatImage
    let config: ChatConfig

    private static let maxDisplayWidth: CGFloat = 280

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if config.showRoleLabels {
                let label = config.style(for: role).label
                if !label.isEmpty {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                }
            }
            CachedImage(url: image.url,
                        intrinsicSize: image.pixelSize,
                        cornerRadius: 10,
                        maxPixelWidth: Self.maxDisplayWidth * 3)
                .frame(maxWidth: Self.maxDisplayWidth, alignment: .leading)
                .accessibilityLabel(image.alt.isEmpty ? Text("Image") : Text(image.alt))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
