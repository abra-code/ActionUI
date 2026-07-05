// Add-ons/ActionUIChat/Tests/OpenAI/OpenAITransportTests.swift
//
// End-to-end tests for OpenAIChatTransport driven by the URLProtocol stub: the full SSE
// streaming path (content assembled into a transcript, usage surfaced), reasoning_content
// interleaved as thoughts, tool_calls rendered as completed cards plus a system notice,
// model "auto" resolution from /models, a non-200 JSON error body, a mid-stream disconnect,
// and cancel-mid-stream finalizing the partial reply. The pure wire parsing is covered in
// OpenAISSEParsingTests.

import XCTest
@testable import ActionUIChatOpenAI
import ActionUIChatCore
import ActionUI

private final class TestLogger: ActionUILogger {
    func log(_ message: String, _ level: LoggerLevel) {}
}

/// A free function (Sendable, unlike a method reference that captures the test case) used as
/// the drain terminal condition.
private func isMessageEnd(_ event: ChatEvent) -> Bool {
    if case .messageEnd = event {
        return true
    }
    return false
}

final class OpenAITransportTests: XCTestCase {

    private let chatPath = "/v1/chat/completions"
    private let modelsPath = "/v1/models"

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func makeTransport(model: String = "test-model", params: [String: Any] = [:]) throws -> OpenAIChatTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        var settings: [String: Any] = ["baseURL": "http://stub.local/v1", "model": model]
        if !params.isEmpty {
            settings["params"] = params
        }
        return try OpenAIChatTransport(config: ChatTransportConfig(settings: settings),
                                       logger: TestLogger(), session: session)
    }

    private func setChatStub(_ sse: String, terminal: StubURLProtocol.Terminal = .finish) {
        StubURLProtocol.setStub(.init(chunks: [Data(sse.utf8)], terminal: terminal), forPath: chatPath)
    }

    /// Drains events until `isTerminal`, with a safety timeout that finishes the stream so a
    /// broken test fails on assertions instead of hanging the suite.
    private func collect(from transport: OpenAIChatTransport,
                         until isTerminal: @Sendable @escaping (ChatEvent) -> Bool) async -> [ChatEvent] {
        let collector = Task { () -> [ChatEvent] in
            var collected: [ChatEvent] = []
            for await event in transport.events {
                collected.append(event)
                if isTerminal(event) {
                    break
                }
            }
            return collected
        }
        let timeout = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await transport.stop()
        }
        let result = await collector.value
        timeout.cancel()
        return result
    }

    // MARK: - Streaming

    func testStreamingAssemblesTranscriptWithUsage() async throws {
        let sse = StubURLProtocol.sseEvent(#"{"choices":[{"delta":{"role":"assistant","content":"Hello"},"finish_reason":null}]}"#)
            + StubURLProtocol.sseEvent(#"{"choices":[{"delta":{"content":" world"},"finish_reason":null}]}"#)
            + StubURLProtocol.sseEvent(#"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#)
            + StubURLProtocol.sseEvent(#"{"choices":[],"usage":{"prompt_tokens":3,"completion_tokens":2,"total_tokens":5}}"#)
            + StubURLProtocol.doneEvent
        setChatStub(sse)
        let transport = try makeTransport()
        await transport.start()
        await transport.send(.prompt(text: "hi"))
        let events = await collect(from: transport, until: isMessageEnd)
        await transport.stop()

        guard case .sessionReady(let sessionID, let options)? = events.first else {
            return XCTFail("expected sessionReady first")
        }
        XCTAssertEqual(sessionID, "openai-sse")
        XCTAssertEqual(options.first?.currentValue, "test-model", "the model surfaces as a read-only option")

        let text = events.compactMap { event -> String? in
            if case .messageDelta(_, let delta) = event {
                return delta
            }
            return nil
        }.joined()
        XCTAssertEqual(text, "Hello world")
        XCTAssertTrue(events.contains { if case .messageStart = $0 { return true }; return false })
        XCTAssertTrue(events.contains { if case .usage(let usage) = $0 { return usage.used == 5 }; return false })
        guard case .messageEnd(_, let stopReason) = events.last else {
            return XCTFail("expected messageEnd last")
        }
        XCTAssertEqual(stopReason, "stop")
    }

    func testReasoningStreamsAsThoughtBeforeMessage() async throws {
        let sse = StubURLProtocol.sseEvent(#"{"choices":[{"delta":{"reasoning_content":"Let me think"}}]}"#)
            + StubURLProtocol.sseEvent(#"{"choices":[{"delta":{"content":"Answer"}}]}"#)
            + StubURLProtocol.sseEvent(#"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#)
            + StubURLProtocol.doneEvent
        setChatStub(sse)
        let transport = try makeTransport()
        await transport.start()
        await transport.send(.prompt(text: "hi"))
        let events = await collect(from: transport, until: isMessageEnd)
        await transport.stop()

        let thoughtIndex = events.firstIndex { if case .thoughtDelta = $0 { return true }; return false }
        let messageStartIndex = events.firstIndex { if case .messageStart = $0 { return true }; return false }
        XCTAssertNotNil(thoughtIndex, "reasoning_content must route to a thought")
        XCTAssertNotNil(messageStartIndex)
        XCTAssertLessThan(thoughtIndex!, messageStartIndex!, "the thought streams before the message opens")
        let thoughtText = events.compactMap { event -> String? in
            if case .thoughtDelta(_, let text) = event {
                return text
            }
            return nil
        }.joined()
        XCTAssertEqual(thoughtText, "Let me think")
    }

    func testToolCallsRenderAsCompletedCardsPlusNotice() async throws {
        let sse = StubURLProtocol.sseEvent(#"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"get_time","arguments":"{\"tz\":"}}]}}]}"#)
            + StubURLProtocol.sseEvent(#"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"UTC\"}"}}]}}]}"#)
            + StubURLProtocol.sseEvent(#"{"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#)
            + StubURLProtocol.doneEvent
        setChatStub(sse)
        let transport = try makeTransport()
        await transport.start()
        await transport.send(.prompt(text: "what time is it"))
        let events = await collect(from: transport, until: isMessageEnd)
        await transport.stop()

        let toolCall = events.compactMap { event -> ToolCallModel? in
            if case .toolCall(let call) = event {
                return call
            }
            return nil
        }.first
        XCTAssertEqual(toolCall?.title, "get_time")
        XCTAssertEqual(toolCall?.status, .completed)
        XCTAssertEqual(toolCall?.id, "call_1")
        XCTAssertEqual(toolCall?.rawInput, "{\n  \"tz\" : \"UTC\"\n}", "the accumulated arguments are pretty-printed")
        XCTAssertTrue(events.contains { if case .system(let text) = $0 { return text.contains("does not execute") }; return false },
                      "a system notice explains tool calls are not executed")
        guard case .messageEnd(_, let stopReason) = events.last else {
            return XCTFail("expected messageEnd last")
        }
        XCTAssertEqual(stopReason, "tool_calls")
    }

    // MARK: - Model resolution

    func testModelAutoResolvesFromModelsEndpoint() async throws {
        let models = Data(#"{"object":"list","data":[{"id":"resolved-model"},{"id":"other"}]}"#.utf8)
        StubURLProtocol.setStub(.init(statusCode: 200, headers: ["Content-Type": "application/json"],
                                      chunks: [models], terminal: .finish), forPath: modelsPath)
        let transport = try makeTransport(model: "auto")
        await transport.start()
        let events = await collect(from: transport) { event in
            if case .sessionReady = event {
                return true
            }
            return false
        }
        await transport.stop()

        guard case .sessionReady(_, let options)? = events.last else {
            return XCTFail("expected sessionReady")
        }
        XCTAssertEqual(options.first?.currentValue, "resolved-model", "model 'auto' resolves to the first /models entry")
    }

    // MARK: - Errors

    func testNon200EmitsErrorWithServerMessage() async throws {
        let body = Data(#"{"error":{"message":"context length exceeded"}}"#.utf8)
        StubURLProtocol.setStub(.init(statusCode: 400, headers: ["Content-Type": "application/json"],
                                      chunks: [body], terminal: .finish), forPath: chatPath)
        let transport = try makeTransport()
        await transport.start()
        await transport.send(.prompt(text: "hi"))
        let events = await collect(from: transport, until: isMessageEnd)
        await transport.stop()

        XCTAssertTrue(events.contains { event in
            if case .error(let message, _) = event {
                return message.contains("context length exceeded") && message.contains("400")
            }
            return false
        }, "a non-200 surfaces the server's error message")
        guard case .messageEnd(_, let stopReason) = events.last else {
            return XCTFail("expected messageEnd last")
        }
        XCTAssertEqual(stopReason, "error")
    }

    func testMidStreamDisconnectKeepsPartialAndErrors() async throws {
        let sse = StubURLProtocol.sseEvent(#"{"choices":[{"delta":{"content":"partial reply"}}]}"#)
        setChatStub(sse, terminal: .failMidStream)
        let transport = try makeTransport()
        await transport.start()
        await transport.send(.prompt(text: "hi"))
        let events = await collect(from: transport, until: isMessageEnd)
        await transport.stop()

        XCTAssertTrue(events.contains { if case .messageDelta(_, let text) = $0 { return text == "partial reply" }; return false },
                      "the partial reply that streamed before the disconnect is kept")
        XCTAssertTrue(events.contains { if case .error = $0 { return true }; return false })
        guard case .messageEnd(_, let stopReason) = events.last else {
            return XCTFail("expected messageEnd last")
        }
        XCTAssertEqual(stopReason, "error")
    }

    // MARK: - Cancel

    func testCancelMidStreamFinalizesPartial() async throws {
        let sse = StubURLProtocol.sseEvent(#"{"choices":[{"delta":{"content":"streaming"}}]}"#)
        setChatStub(sse, terminal: .hang)   // deliver the delta, then never finish
        let transport = try makeTransport()
        await transport.start()
        await transport.send(.prompt(text: "hi"))

        let collector = Task { () -> [ChatEvent] in
            var collected: [ChatEvent] = []
            for await event in transport.events {
                collected.append(event)
                if case .messageEnd = event {
                    break
                }
            }
            return collected
        }
        try await Task.sleep(nanoseconds: 250_000_000)   // let the delta stream
        await transport.send(.cancel)
        let events = await collector.value
        await transport.stop()

        XCTAssertTrue(events.contains { if case .messageDelta(_, let text) = $0 { return text == "streaming" }; return false },
                      "the partial text streamed before cancel is finalized")
        guard case .messageEnd(_, let stopReason) = events.last else {
            return XCTFail("expected messageEnd last")
        }
        XCTAssertEqual(stopReason, "cancelled")
    }

    // MARK: - Wire history

    func testSuccessfulTurnRecordsUserAndAssistantInHistory() async throws {
        let sse = StubURLProtocol.sseEvent(#"{"choices":[{"delta":{"content":"Hi there"}}]}"#)
            + StubURLProtocol.sseEvent(#"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#)
            + StubURLProtocol.doneEvent
        setChatStub(sse)
        let transport = try makeTransport()
        await transport.start()
        await transport.send(.prompt(text: "hello"))
        _ = await collect(from: transport, until: isMessageEnd)
        let history = transport.conversationSnapshot
        await transport.stop()

        XCTAssertEqual(history.count, 2, "a successful turn records the user and assistant messages")
        XCTAssertEqual(history.first?["role"] as? String, "user")
        XCTAssertEqual(history.first?["content"] as? String, "hello")
        XCTAssertEqual(history.last?["role"] as? String, "assistant")
        XCTAssertEqual(history.last?["content"] as? String, "Hi there")
    }

    func testHardFailureDropsDanglingUserMessage() async throws {
        let body = Data(#"{"error":{"message":"server error"}}"#.utf8)
        StubURLProtocol.setStub(.init(statusCode: 500, headers: ["Content-Type": "application/json"],
                                      chunks: [body], terminal: .finish), forPath: chatPath)
        let transport = try makeTransport()
        await transport.start()
        await transport.send(.prompt(text: "hello"))
        _ = await collect(from: transport, until: isMessageEnd)
        let history = transport.conversationSnapshot
        await transport.stop()

        XCTAssertTrue(history.isEmpty, "a hard failure with no reply drops the user message so retries do not accumulate back-to-back user turns")
    }

    // MARK: - Construction

    func testMissingBaseURLThrows() {
        XCTAssertThrowsError(try OpenAIChatTransport(config: ChatTransportConfig(settings: [:]), logger: TestLogger()))
        XCTAssertThrowsError(try OpenAIChatTransport(config: ChatTransportConfig(settings: ["baseURL": ""]), logger: TestLogger()))
    }
}
