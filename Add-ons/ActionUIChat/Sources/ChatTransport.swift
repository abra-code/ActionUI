// Add-ons/ActionUIChat/Sources/ChatTransport.swift
//
// The transport abstraction (protocol-agnostic) plus the built-in `local` transport
// and the selection factory.
//
// A transport is the ONLY layer that knows a wire protocol. It emits a normalized
// `ChatEvent` stream and accepts normalized `ChatCommand`s, so the store / view above
// it are identical no matter which protocol is active. M1 ships one transport,
// `local`; the ACP and SSE transports (later milestones) conform to the same protocol
// and are selected by `properties.protocol`.

import Foundation
import ActionUI

/// One wire protocol's adapter. `Sendable` so the store can drive it from async
/// contexts; `events` is a single-consumer stream the store drains.
protocol ChatTransport: AnyObject, Sendable {
    init(config: [String: Any], logger: any ActionUILogger) throws
    func start() async
    func send(_ command: ChatCommand) async
    var events: AsyncStream<ChatEvent> { get }
    func stop() async
}

/// The `local` transport: no wire. It is the simplest scripted demo / person-to-person
/// backend - the "Tier A" path made first-class. In M1 it ECHOES: each submitted prompt
/// produces an agent reply streamed back word-by-word, which proves the element
/// end-to-end (append -> stream deltas -> finalize, auto-scroll, role styling) with zero
/// protocol risk. A host that wants to drive the transcript itself (rather than echo)
/// will get a push API here in a later milestone; `echo` (config, default true) gates the
/// demo reply.
///
/// `@unchecked Sendable`: the only mutable state (the reply counter and the in-flight
/// reply task) is guarded by `lock`; `events` / `continuation` / `echo` are immutable and
/// the AsyncStream continuation is itself thread-safe to yield from any context.
final class LocalChatTransport: ChatTransport, @unchecked Sendable {

    let events: AsyncStream<ChatEvent>
    private let continuation: AsyncStream<ChatEvent>.Continuation
    private let echo: Bool
    private let replyStyle: String          // "echo" (default) | "markdown"
    private let lock = NSLock()
    private var replyCounter = 0
    private var replyTask: Task<Void, Never>?

    // A non-throwing init satisfies the throwing protocol requirement; the local
    // transport never fails to construct. `logger` is accepted for protocol conformance
    // but unused. `reply` selects the demo content: "echo" repeats the prompt; "markdown"
    // streams a Markdown showcase (used by the M2 streaming-Markdown demo).
    init(config: [String: Any], logger: any ActionUILogger) {
        self.echo = (config["echo"] as? Bool) ?? true
        self.replyStyle = (config["reply"] as? String) ?? "echo"
        var captured: AsyncStream<ChatEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .unbounded) { captured = $0 }
        self.continuation = captured
    }

    func start() async {
        continuation.yield(.sessionReady(sessionID: "local"))
    }

    func send(_ command: ChatCommand) async {
        switch command {
        case .prompt(let text):
            guard echo else { return }
            let itemID = lock.withLock { () -> String in
                replyCounter += 1
                return "agent-\(replyCounter)"
            }
            let task = Task { [weak self] in
                guard let self else { return }
                await self.streamEcho(itemID: itemID, prompt: text)
            }
            lock.withLock { replyTask = task }
        case .cancel:
            lock.withLock { replyTask }?.cancel()
        }
    }

    func stop() async {
        lock.withLock { replyTask }?.cancel()
        continuation.finish()
    }

    /// Streams a canned reply chunk-by-chunk with a small per-chunk delay so streaming is visibly
    /// progressive. Chunks preserve whitespace and newlines (so Markdown layout - blank lines, code
    /// blocks - streams faithfully). Honors cancellation (the Stop affordance / `.cancel`).
    private func streamEcho(itemID: String, prompt: String) async {
        continuation.yield(.messageStart(itemID: itemID, role: .agent))
        let reply = ChatReplyContent.make(style: replyStyle, prompt: prompt)
        for chunk in ChatReplyContent.streamingChunks(reply) {
            if Task.isCancelled {
                break
            }
            try? await Task.sleep(nanoseconds: 45_000_000)   // ~45 ms/chunk
            continuation.yield(.messageDelta(itemID: itemID, text: chunk))
        }
        continuation.yield(.messageEnd(itemID: itemID, stopReason: Task.isCancelled ? "cancelled" : "end_turn"))
    }
}

/// Canned reply content for the local transport. `echo` repeats the prompt; `markdown` returns a
/// showcase that exercises the M2 Markdown renderer (headings, emphasis, code, lists, a quote, a
/// table, a rule) and embeds the prompt as a quote.
enum ChatReplyContent {

    static func make(style: String, prompt: String) -> String {
        switch style {
        case "markdown":
            return markdownShowcase(prompt: prompt)
        default:
            return "You said: \(prompt)"
        }
    }

    private static func markdownShowcase(prompt: String) -> String {
        let oneLine = prompt.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let quoted = escapeInline(oneLine.isEmpty ? "(empty message)" : oneLine)
        return """
        ## Streaming Markdown

        > \(quoted)

        Here are the basics, **streamed** chunk by chunk:

        - **bold**, *italic*, ~~strike~~, and `inline code`
        - a [link](https://www.swift.org)
        - a nested list:
          - sub item one
          - sub item two

        > A short blockquote, to show quoting.

        ---

        Code and tables render too:

        ```swift
        func greet(_ name: String) -> String {
            return "Hello, \\(name)!"
        }
        ```

        | Feature  | Status |
        | -------- | :----: |
        | Headings | ok     |
        | Code     | ok     |
        | Tables   | ok     |

        That is all.
        """
    }

    private static func escapeInline(_ s: String) -> String {
        var out = ""
        for c in s {
            if "\\`*_[]()#~|".contains(c) {
                out.append("\\")
            }
            out.append(c)
        }
        return out
    }

    /// Splits text into chunks that each preserve their trailing whitespace, so streaming the chunks
    /// one at a time reproduces the source exactly (blank lines, indentation, code layout included).
    /// A boundary falls where a non-space character follows whitespace - i.e. each chunk is a word
    /// plus the whitespace that trails it.
    static func streamingChunks(_ text: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        for ch in text {
            let isSpace = ch == " " || ch == "\n" || ch == "\t"
            if !isSpace, let last = current.last, last == " " || last == "\n" || last == "\t" {
                chunks.append(current)
                current = ""
            }
            current.append(ch)
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }
}

/// Selects and builds the transport for a config. M1 implements `local`; any other
/// protocol warns (already flagged in validation) and falls back to `local`, so a
/// document that names an unimplemented transport still renders and degrades safely.
enum ChatTransportFactory {
    static func make(_ config: ChatConfig, logger: any ActionUILogger) -> any ChatTransport {
        switch config.protocolName {
        case "local":
            return LocalChatTransport(config: config.transport, logger: logger)
        default:
            logger.log("Chat transport '\(config.protocolName)' unavailable; using 'local'", .warning)
            return LocalChatTransport(config: config.transport, logger: logger)
        }
    }
}
