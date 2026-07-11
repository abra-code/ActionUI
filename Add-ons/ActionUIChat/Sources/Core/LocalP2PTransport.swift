// Add-ons/ActionUIChat/Sources/Core/LocalP2PTransport.swift
//
// The `local-p2p` transport: a scripted, no-wire person-to-person / group backend that
// exercises the entire v2 vocabulary so the dual-alignment UI, the rows, paging, and the
// affordance gating all run end-to-end with no real transport. It is the demo content for
// the ChatPeople / ChatGroup example documents and the behavioral fixture source.
//
// Selected by `config.protocol == "local-p2p"`; `config.transport.scenario` picks "people"
// (a 1:1 chat, default) or "group" (four participants with member / call events). It
// advertises ALL capabilities, seeds a short recent conversation (timestamps, delivery
// statuses, a reaction, an edit, a tombstone, a file, a voice message), answers each user
// send with a scripted reply and a typing burst, honors reactions / edits / deletes /
// resends locally, and serves synthetic paged history on `.loadEarlier`.
//
// `@unchecked Sendable`: all mutable state is guarded by `lock`; the AsyncStream
// continuation is safe to yield from any context.

import Foundation
import CoreGraphics

final class LocalP2PTransport: ChatTransport, @unchecked Sendable {

    let events: AsyncStream<ChatEvent>
    private let continuation: AsyncStream<ChatEvent>.Continuation
    let capabilities = ChatTransportCapabilities(
        paging: true, typing: true, reactions: true, editing: true,
        deletion: true, replies: true, readReceipts: true, fileTransfer: true)

    private let scenario: String            // "people" | "group"
    private let stepDelay: UInt64           // ns between scripted beats (0 in tests)
    private let lock = NSLock()
    private var replyCounter = 0            // peer / generated ids (peer-N)
    private var ownSendCounter = 0          // reconstructs the store's optimistic "user-N" send ids
    private var tasks: [Task<Void, Never>] = []

    // Synthetic older history for paging: OLDEST first. `.loadEarlier` serves pages from the tail.
    private var history: [ChatItem] = []
    private var historyCursor = 0           // how many of `history` (from the end) have been served

    // The other party in the 1:1 chat / the primary correspondent in the group.
    private let peerID = "alex"
    private let peerName = "Alex"

    init(config: ChatTransportConfig) {
        self.scenario = config.string("scenario") ?? "people"
        let stepMs = config.int("stepMs") ?? 700
        self.stepDelay = UInt64(max(0, stepMs)) * 1_000_000
        var captured: AsyncStream<ChatEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .unbounded) { captured = $0 }
        self.continuation = captured
    }

    // MARK: - Lifecycle

    func start() async {
        continuation.yield(.sessionReady(sessionID: "local-p2p", configOptions: []))
        continuation.yield(.participantsChanged(roster()))
        buildHistory()
        for event in seedConversation() {
            continuation.yield(event)
        }
        // A little life after load: the peer types, then sends one more line. Only in the paced
        // (interactive demo) mode - at stepMs 0 (tests / fixtures) the seed is deterministic.
        guard stepDelay > 0 else {
            return
        }
        spawn { [weak self] in
            guard let self else { return }
            await self.pause(2)
            self.emitPeerTyping()
            await self.pause(1)
            let id = self.nextID(prefix: "peer")
            self.continuation.yield(.typingChanged(isTyping: false, senderID: self.peerID, senderName: self.peerName))
            self.continuation.yield(.messageReceived(self.peerMessage(id: id, text: "Anyway - talk later!",
                                                                      minutesAgo: 0)))
        }
    }

    func stop() async {
        lock.withLock { tasks }.forEach { $0.cancel() }
        continuation.finish()
    }

    // MARK: - Commands

    func send(_ command: ChatCommand) async {
        switch command {
        case .prompt(let text), .sendMessage(let text, _):
            handleUserSend(text: text, replyTo: replyToOf(command))

        case .toggleReaction(let itemID, let emoji, let add):
            // Reflect the toggle authoritatively (the store sent optimistic intent; we echo the result).
            let reactions = add ? [Reaction(emoji: emoji, count: 1, mine: true)] : []
            continuation.yield(.reactionsChanged(itemID: itemID, reactions: reactions))

        case .editMessage(let itemID, let newText):
            continuation.yield(.messageEdited(itemID: itemID, newText: newText, editedAt: Self.stamp(minutesAgo: 0)))

        case .deleteMessage(let itemID):
            continuation.yield(.messageDeleted(itemID: itemID))

        case .resendMessage(let itemID):
            spawn { [weak self] in
                guard let self else { return }
                self.continuation.yield(.messageStatusChanged(itemID: itemID, status: .sending))
                await self.pause(1)
                self.continuation.yield(.messageStatusWatermark(status: .delivered, upToItemID: itemID))
            }

        case .loadEarlier(_, let limit):
            servePage(limit: limit)

        case .cancelFileTransfer(let itemID):
            continuation.yield(.fileProgress(itemID: itemID, progress: nil, transferStatus: .cancelled))

        case .markRead, .setTyping, .cancel, .permissionResponse, .setConfigOption:
            break
        }
    }

    // MARK: - User send -> scripted reply

    private func handleUserSend(text: String, replyTo: String?) {
        // The store already appended the optimistic local message with id user-N and status .sending.
        // Drive its delivery ladder, then answer with a scripted peer reply and a typing burst.
        spawn { [weak self] in
            guard let self else { return }
            let ownID = self.currentOwnMessageID()
            await self.pause(1)
            if let ownID {
                self.continuation.yield(.messageStatusChanged(itemID: ownID, status: .sent))
                await self.pause(1)
                self.continuation.yield(.messageStatusChanged(itemID: ownID, status: .delivered))
            }
            self.emitPeerTyping()
            await self.pause(2)
            self.continuation.yield(.typingChanged(isTyping: false, senderID: self.peerID, senderName: self.peerName))
            let replyID = self.nextID(prefix: "peer")
            self.continuation.yield(.messageReceived(self.peerMessage(
                id: replyID, text: self.scriptedReply(to: text), minutesAgo: 0)))
            // The peer reads our message.
            if let ownID {
                await self.pause(1)
                self.continuation.yield(.messageStatusWatermark(status: .read, upToItemID: ownID))
            }
        }
    }

    // The store labels our optimistic sends user-1, user-2, ... (its localCounter, which - absent a
    // restore or system/error item, neither of which this mock emits - advances once per send). We
    // track the same count so the delivery ladder targets the real optimistic message id.
    private func currentOwnMessageID() -> String? {
        lock.withLock {
            ownSendCounter += 1
            return "user-\(ownSendCounter)"
        }
    }

    private func scriptedReply(to text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().contains("?") {
            return "Good question - let me check and get back to you."
        }
        return "Got it: \u{201C}\(trimmed.prefix(80))\u{201D}. Sounds good!"
    }

    // MARK: - Seeded conversation

    private func seedConversation() -> [ChatEvent] {
        var events: [ChatEvent] = []
        if scenario == "group" {
            events.append(.memberEvent(MemberEvent(id: "ev-join-1", timestamp: Self.stamp(daysAgo: 1, minute: 0),
                                                   kind: .joined, subjectName: "Sam")))
        }
        events.append(.messageReceived(peerMessage(id: "seed-1", text: "Hey! Are we still on for tomorrow?",
                                                   daysAgo: 1, minute: 1)))
        events.append(.messageReceived(peerMessage(id: "seed-2", text: "I found a great spot for lunch.",
                                                   daysAgo: 1, minute: 1,
                                                   reactions: [Reaction(emoji: "\u{1F44D}", count: 1, mine: true)])))
        events.append(.messageReceived(ownMessage(id: "seed-3", text: "Yes! Sounds perfect.",
                                                  daysAgo: 0, minute: 0, status: .read)))
        events.append(.messageReceived(ownMessage(id: "seed-4", text: "Let me double-check the time.",
                                                  daysAgo: 0, minute: 1, status: .delivered,
                                                  editedAt: Self.stamp(daysAgo: 0, minute: 2))))
        if scenario == "group" {
            events.append(.callEvent(CallEvent(id: "call-1", timestamp: Self.stamp(daysAgo: 0, minute: 3),
                                               kind: .missedIncoming, isVideo: true)))
            events.append(.memberEvent(MemberEvent(id: "ev-rename-1", timestamp: Self.stamp(daysAgo: 0, minute: 4),
                                                   kind: .renamed, actorName: "Alex", detail: "Weekend Trip")))
        }
        // A file and a voice message from the peer.
        events.append(.fileAdded(ChatFile(id: "file-1", role: .remote, senderID: peerID, senderName: peerName,
                                          timestamp: Self.stamp(daysAgo: 0, minute: 5), name: "itinerary.pdf",
                                          sizeBytes: 284_160, url: URL(string: "https://example.test/itinerary.pdf"),
                                          kind: .file, transferStatus: .completed)))
        events.append(.fileAdded(ChatFile(id: "voice-1", role: .remote, senderID: peerID, senderName: peerName,
                                          timestamp: Self.stamp(daysAgo: 0, minute: 6), name: "voice-message.m4a",
                                          sizeBytes: 51_200, url: URL(string: "https://example.test/voice.m4a"),
                                          kind: .voice, durationSeconds: 14, transferStatus: .completed)))
        return events
    }

    // MARK: - Synthetic paging

    private func buildHistory() {
        // 200 older messages, OLDEST first, alternating parties, a few days back.
        var items: [ChatItem] = []
        for index in 0..<200 {
            let mine = index % 2 == 1
            let id = "hist-\(index)"
            let day = 6 - (index / 40)   // spread across several older days for day separators
            let text = "Earlier message #\(index + 1)"
            if mine {
                items.append(.message(ownMessage(id: id, text: text, daysAgo: day, minute: index % 40, status: .read)))
            } else {
                items.append(.message(peerMessage(id: id, text: text, daysAgo: day, minute: index % 40)))
            }
        }
        lock.withLock {
            history = items
            historyCursor = 0
        }
    }

    private func servePage(limit: Int) {
        let (page, hasMore) = lock.withLock { () -> ([ChatItem], Bool) in
            let remaining = history.count - historyCursor
            guard remaining > 0 else {
                return ([], false)
            }
            let take = min(limit, remaining)
            // Serve the tail-most unseen slice, in chronological order.
            let upper = history.count - historyCursor
            let lower = upper - take
            let slice = Array(history[lower..<upper])
            historyCursor += take
            return (slice, historyCursor < history.count)
        }
        spawn { [weak self] in
            guard let self else { return }
            await self.pause(1)
            self.continuation.yield(.historyPage(items: page, hasMore: hasMore))
        }
    }

    // MARK: - Helpers

    private func roster() -> [Participant] {
        var people = [
            Participant(id: "me", name: "You", isSelf: true),
            Participant(id: peerID, name: peerName, avatarURL: nil),
        ]
        if scenario == "group" {
            people.append(Participant(id: "sam", name: "Sam"))
            people.append(Participant(id: "jordan", name: "Jordan"))
        }
        return people
    }

    private func emitPeerTyping() {
        continuation.yield(.typingChanged(isTyping: true, senderID: peerID, senderName: peerName))
    }

    private func peerMessage(id: String, text: String, daysAgo: Int = 0, minute: Int = 0, minutesAgo: Int? = nil,
                             reactions: [Reaction]? = nil) -> ChatMessage {
        ChatMessage(id: id, role: .remote, text: text, isStreaming: false, senderID: peerID, senderName: peerName,
                    timestamp: minutesAgo.map { Self.stamp(minutesAgo: $0) } ?? Self.stamp(daysAgo: daysAgo, minute: minute),
                    reactions: reactions)
    }

    private func ownMessage(id: String, text: String, daysAgo: Int = 0, minute: Int = 0, status: MessageStatus,
                            editedAt: String? = nil) -> ChatMessage {
        ChatMessage(id: id, role: .local, text: text, isStreaming: false, senderID: "me",
                    timestamp: Self.stamp(daysAgo: daysAgo, minute: minute), status: status, editedAt: editedAt)
    }

    private func replyToOf(_ command: ChatCommand) -> String? {
        if case .sendMessage(_, let replyTo) = command {
            return replyTo
        }
        return nil
    }

    private func nextID(prefix: String) -> String {
        lock.withLock {
            replyCounter += 1
            return "\(prefix)-\(replyCounter)"
        }
    }

    private func spawn(_ body: @escaping @Sendable () async -> Void) {
        let task = Task(operation: body)
        lock.withLock { tasks.append(task) }
    }

    private func pause(_ beats: Int) async {
        guard stepDelay > 0 else { return }
        try? await Task.sleep(nanoseconds: stepDelay * UInt64(beats))
    }

    // A stable clock for the scripted timestamps: a fixed "now" so the seeded conversation is
    // deterministic (the demo shows dated day separators; tests get reproducible times).
    nonisolated(unsafe) private static let base: Date = ISO8601DateFormatter().date(from: "2026-07-10T15:00:00Z")!

    private static func stamp(daysAgo: Int = 0, minute: Int = 0, minutesAgo: Int? = nil) -> String {
        let seconds: TimeInterval
        if let minutesAgo {
            seconds = -Double(minutesAgo) * 60
        } else {
            seconds = -Double(daysAgo) * 86_400 + Double(minute) * 60
        }
        let date = base.addingTimeInterval(seconds)
        return isoFormatter.string(from: date)
    }

    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
