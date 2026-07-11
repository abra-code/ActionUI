// Add-ons/ActionUIChat/Sources/Core/ChatDualTranscript.swift
//
// The dual-alignment (person-to-person / group) transcript rows: the messaging-app layout
// where your own messages align trailing with the role tint and everyone else's align
// leading. Driven by `appearance.alignment: "dual"`; single alignment keeps the exact v1
// rows in ChatRootView. Run grouping, day separators, and timestamp parsing come from the
// pure ChatTranscriptLayout helpers - these views only place what those compute:
//   - a sender-name label above the FIRST message of a run (groups / showRoleLabels),
//   - an avatar (or initials disc) beside the LAST message of an incoming run,
//   - a timestamp caption (+ an "(edited)" badge) below the LAST message of a run,
//   - a delivery-status caption under the last OWN message of a run (Failed -> tap to retry),
//   - a "Message deleted" tombstone, and a quoted-excerpt block for a reply.
// Member/call/file/voice rows and the reaction chips / interactive reply-quote are later stages.

import SwiftUI
import ActionUI
import RichText
import AsyncImageCache
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// One transcript item reduced to what a dual row renders: the resolved sender identity, the
/// parsed timestamp, self-authorship, and the run/day placement from ChatTranscriptLayout.
struct DualRowContext: Identifiable {
    let id: String
    let item: ChatItem
    let info: ChatTranscriptLayout.Info
    let isSelf: Bool
    let senderName: String?
    let avatarURL: String?
    let timestamp: Date?
}

/// The message affordances the transcript offers, each already gated (features AND capabilities) by
/// the caller, plus the closures that run them. Copy is always available (ungated); the gated flags
/// drive whether Reply / Edit / Delete / React appear.
struct DualRowActions {
    var canReply = false
    var canEdit = false
    var canDelete = false
    var canReact = false
    var reply: (ChatMessage) -> Void = { _ in }
    var edit: (ChatMessage) -> Void = { _ in }
    var delete: (ChatMessage) -> Void = { _ in }
    var toggleReaction: (_ itemID: String, _ emoji: String) -> Void = { _, _ in }
    var jumpTo: (String) -> Void = { _ in }

    /// The fixed quick-reaction row shown at the top of the context menu (Unicode order per the plan):
    /// thumbs up, heart, tears of joy, open mouth, crying, folded hands.
    static let quickReactions = ["\u{1F44D}", "\u{2764}\u{FE0F}", "\u{1F602}", "\u{1F62E}", "\u{1F622}", "\u{1F64F}"]
}

/// Renders one dual-alignment row (dispatch by item kind). The caller places the optional day
/// separator and the inter-run spacing; this view renders the item itself.
struct DualTranscriptRow: View {
    let ctx: DualRowContext
    let config: ChatConfig
    let maxBubbleWidth: CGFloat
    let showsSenderNames: Bool
    let actions: DualRowActions
    let highlighted: Bool
    let onResend: (String) -> Void

    var body: some View {
        switch ctx.item {
        case .message(let message):
            DualMessageRow(ctx: ctx, message: message, config: config, maxBubbleWidth: maxBubbleWidth,
                           showsSenderNames: showsSenderNames, actions: actions, highlighted: highlighted,
                           onResend: onResend)
        case .image(_, let role, let image):
            // An image is a leading/trailing bubble too; reuse the shared image view inside the gutter frame.
            DualImageRow(ctx: ctx, role: role, image: image, config: config, maxBubbleWidth: maxBubbleWidth)
        case .system(_, let text):
            CenteredCaption(text: text, systemImage: nil, tint: .secondary)
        case .error(_, let text):
            CenteredCaption(text: text, systemImage: "exclamationmark.triangle", tint: .red)
        case .thought, .toolCall, .memberEvent, .callEvent, .file:
            // Agentic surfaces are not part of a P2P conversation; member/call/file rows are built in P6.
            EmptyView()
        }
    }
}

// MARK: - Message row (dual)

private struct DualMessageRow: View {
    let ctx: DualRowContext
    let message: ChatMessage
    let config: ChatConfig
    let maxBubbleWidth: CGFloat
    let showsSenderNames: Bool
    let actions: DualRowActions
    let highlighted: Bool
    let onResend: (String) -> Void

    private var isSelf: Bool { ctx.isSelf }
    private var isFirstInRun: Bool { ctx.info.isFirstInRun }
    private var isLastInRun: Bool { ctx.info.isLastInRun }
    private var isTombstone: Bool { message.deleted == true }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isSelf {
                Spacer(minLength: 40)
            } else if config.showAvatars {
                avatarGutter
            }

            VStack(alignment: isSelf ? .trailing : .leading, spacing: 2) {
                if !isSelf, isFirstInRun, showsSenderNames, let name = ctx.senderName, !name.isEmpty {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                bubble
                // Chips are an affordance, so they are gated on canReact (features AND capabilities),
                // never on data presence alone - a seeded / inbound message can carry reaction data
                // even when the document/transport does not enable reactions.
                if actions.canReact, let reactions = message.reactions, !reactions.isEmpty {
                    ReactionChips(reactions: reactions, alignSelf: isSelf) { emoji in
                        actions.toggleReaction(message.id, emoji)
                    }
                }
                if isLastInRun {
                    captionRow
                }
            }
            .frame(maxWidth: maxBubbleWidth, alignment: isSelf ? .trailing : .leading)

            if !isSelf {
                Spacer(minLength: 40)
            }
        }
        .frame(maxWidth: .infinity, alignment: isSelf ? .trailing : .leading)
    }

    @ViewBuilder
    private var bubble: some View {
        Group {
            if isTombstone {
                Text("Message deleted")
                    .italic()
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    if let reply = message.replyTo {
                        Button { actions.jumpTo(reply.itemID) } label: { ReplyQuote(reply: reply) }
                            .buttonStyle(.plain)
                    }
                    content
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.accentColor, lineWidth: highlighted ? 2 : 0)
        )
        // No maxWidth:.infinity here: the bubble hugs its content (up to the column's maxBubbleWidth),
        // the messaging-app idiom, rather than filling the column like a v1 full-width row.
        .contextMenu { if !isTombstone { bubbleMenu } }
    }

    // The message context menu: a quick-reaction row on top (when reactions are enabled), then the
    // gated actions and the always-available Copy. Edit / Delete are own-message only (the caller's
    // gate already accounts for that via canEdit / canDelete plus isSelf).
    @ViewBuilder
    private var bubbleMenu: some View {
        if actions.canReact {
            ControlGroup {
                ForEach(DualRowActions.quickReactions, id: \.self) { emoji in
                    Button(emoji) { actions.toggleReaction(message.id, emoji) }
                }
            }
        }
        if actions.canReply {
            Button { actions.reply(message) } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
        }
        if actions.canEdit, isSelf {
            Button { actions.edit(message) } label: { Label("Edit", systemImage: "pencil") }
        }
        Button { copyText() } label: { Label("Copy", systemImage: "doc.on.doc") }
        if actions.canDelete, isSelf {
            Button(role: .destructive) { actions.delete(message) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func copyText() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text, forType: .string)
        #else
        UIPasteboard.general.string = message.text
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if message.text.isEmpty && message.isStreaming {
            Text("\u{2026}").foregroundStyle(.secondary)
        } else {
            RichText(markdown: message.text)
        }
    }

    private var bubbleBackground: Color {
        if isSelf {
            return ChatTint.color(for: config.style(for: message.role).tint).opacity(0.22)
        }
        return Color.secondary.opacity(0.14)
    }

    // The avatar renders beside the LAST message of an incoming run; earlier rows reserve the gutter
    // (a clear spacer) so the bubbles stay aligned.
    @ViewBuilder
    private var avatarGutter: some View {
        if isLastInRun {
            AvatarView(url: ctx.avatarURL, name: ctx.senderName, size: 28)
        } else {
            Color.clear.frame(width: 28, height: 1)
        }
    }

    // Below the last message of a run: a timestamp (+ "(edited)"), and for an own run the delivery status.
    @ViewBuilder
    private var captionRow: some View {
        let timeText = timestampCaption
        if isSelf {
            HStack(spacing: 4) {
                if let timeText {
                    Text(timeText).font(.caption2).foregroundStyle(.secondary)
                }
                if config.showDeliveryStatus, let status = message.status {
                    DeliveryStatusCaption(status: status) { onResend(message.id) }
                }
            }
            .padding(.horizontal, 4)
        } else if let timeText {
            Text(timeText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var timestampCaption: String? {
        guard config.showTimestamps, let date = ctx.timestamp else {
            // An edited message with no timestamp still shows the edited badge.
            return message.editedAt != nil ? "(edited)" : nil
        }
        var text = ChatDateFormat.shortTime(date)
        if message.editedAt != nil {
            text += " \u{00B7} (edited)"
        }
        return text
    }
}

// MARK: - Image row (dual)

private struct DualImageRow: View {
    let ctx: DualRowContext
    let role: ChatRole
    let image: ChatImage
    let config: ChatConfig
    let maxBubbleWidth: CGFloat

    private var isSelf: Bool { ctx.isSelf }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isSelf {
                Spacer(minLength: 40)
            } else if config.showAvatars {
                if ctx.info.isLastInRun {
                    AvatarView(url: ctx.avatarURL, name: ctx.senderName, size: 28)
                } else {
                    Color.clear.frame(width: 28, height: 1)
                }
            }
            CachedImage(url: image.url, intrinsicSize: image.pixelSize, cornerRadius: 12,
                        maxPixelWidth: maxBubbleWidth * 3)
                .frame(maxWidth: min(maxBubbleWidth, 280), alignment: isSelf ? .trailing : .leading)
                .accessibilityLabel(image.alt.isEmpty ? Text("Image") : Text(image.alt))
            if !isSelf {
                Spacer(minLength: 40)
            }
        }
        .frame(maxWidth: .infinity, alignment: isSelf ? .trailing : .leading)
    }
}

// MARK: - Reply quote (display; the tap-to-scroll + compose banner are P5)

private struct ReplyQuote: View {
    let reply: ReplyRef

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.accentColor.opacity(0.6))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                if let sender = reply.senderName, !sender.isEmpty {
                    Text(sender).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text(reply.excerpt).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

// MARK: - Reaction chips

/// A wrapping row of reaction chips under a bubble: emoji + count, `mine` tinted; tap toggles.
private struct ReactionChips: View {
    let reactions: [Reaction]
    let alignSelf: Bool
    let toggle: (String) -> Void

    var body: some View {
        ReactionFlow(spacing: 4) {
            ForEach(reactions, id: \.emoji) { reaction in
                Button { toggle(reaction.emoji) } label: {
                    HStack(spacing: 3) {
                        Text(reaction.emoji)
                        if reaction.count > 1 {
                            Text("\(reaction.count)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(reaction.mine ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.14),
                                in: Capsule())
                    .overlay(Capsule().strokeBorder(reaction.mine ? Color.accentColor.opacity(0.5) : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignSelf ? .trailing : .leading)
        .padding(.horizontal, 2)
    }
}

/// A minimal wrapping (flow) layout: lays subviews left to right, wrapping to a new line when the
/// proposed width is exceeded. Used for the reaction chip row.
private struct ReactionFlow: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                widest = max(widest, rowWidth)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        widest = max(widest, rowWidth)
        return CGSize(width: min(maxWidth, widest), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Delivery status caption

private struct DeliveryStatusCaption: View {
    let status: MessageStatus
    let onRetry: () -> Void

    var body: some View {
        switch status {
        case .sending:
            Text("Sending\u{2026}").font(.caption2).foregroundStyle(.secondary)
        case .sent:
            Text("Sent").font(.caption2).foregroundStyle(.secondary)
        case .delivered:
            Text("Delivered").font(.caption2).foregroundStyle(.secondary)
        case .read:
            Text("Read").font(.caption2).foregroundStyle(.tint)
        case .failed:
            Button(action: onRetry) {
                Label("Failed \u{2013} tap to retry", systemImage: "exclamationmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Avatar

/// A sender avatar: the resolved image, or a colored initials disc when no avatar resolves.
struct AvatarView: View {
    let url: String?
    let name: String?
    let size: CGFloat

    var body: some View {
        if let url, let parsed = URL(string: url) {
            CachedImage(url: parsed, intrinsicSize: nil, cornerRadius: size / 2, maxPixelWidth: size * 3)
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(discColor.opacity(0.25))
                .frame(width: size, height: size)
                .overlay(
                    Text(initials)
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(discColor)
                )
        }
    }

    private var initials: String {
        let words = (name ?? "").split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    // A stable per-name hue so a participant keeps the same disc color across the transcript.
    private var discColor: Color {
        let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .red]
        let key = name ?? ""
        var hash = 5381
        for byte in key.utf8 {
            hash = ((hash << 5) &+ hash) &+ Int(byte)
        }
        return palette[abs(hash) % palette.count]
    }
}

// MARK: - Centered caption + day separator

/// A centered caption row (system notice, and the visual family member / call events will reuse in P6).
struct CenteredCaption: View {
    let text: String
    let systemImage: String?
    let tint: Color

    var body: some View {
        Group {
            if let systemImage {
                Label(text, systemImage: systemImage)
            } else {
                Text(text)
            }
        }
        .font(.caption)
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 2)
    }
}

/// A centered date caption inserted between items when the calendar day changes.
struct DaySeparatorRow: View {
    let date: Date

    var body: some View {
        Text(ChatDateFormat.daySeparator(date))
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 6)
    }
}

// MARK: - Date formatting

enum ChatDateFormat {
    static func shortTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// "Today" / "Yesterday" / a medium date for the day separator.
    static func daySeparator(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        return dayFormatter.string(from: date)
    }

    nonisolated(unsafe) private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    nonisolated(unsafe) private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
