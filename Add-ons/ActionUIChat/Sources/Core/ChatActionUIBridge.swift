// Add-ons/ActionUIChat/Sources/Core/ChatActionUIBridge.swift
//
// The ActionUI side of the component's host contracts, kept in one add-on-only file:
// the logger adapter (ActionUILogger -> ChatLogger) and the ViewModel conformance to
// ChatContentSource (states["content"] / states["config"] observation). The component
// itself never imports ActionUI.

import Foundation
import Combine
import ActionUI

/// Wraps the host's ActionUILogger as the component's ChatLogger. Levels map by raw value
/// (the two enums are defined with identical raw values).
struct ChatLoggerAdapter: ChatLogger {
    let base: any ActionUILogger
    func log(_ message: String, _ level: ChatLogLevel) {
        base.log(message, LoggerLevel(rawValue: level.rawValue) ?? .info)
    }
}

extension ViewModel: ChatContentSource {
    public func observeChatContent(_ handler: @escaping (Any?) -> Void) -> AnyCancellable {
        $states.sink { handler($0["content"]) }
    }
    public func observeChatConfig(_ handler: @escaping (Any?) -> Void) -> AnyCancellable {
        $states.sink { handler($0["config"]) }
    }
    /// states["append"]: ONE ChatItem, added to the end of the live transcript.
    ///
    /// The sibling of states["content"], for the case that channel cannot serve: content REPLACES
    /// the transcript and re-primes the agent, so a host wanting to add a single line to a
    /// conversation already on screen had to re-prime the whole thing to show it. Setting this
    /// state appends and nothing else - no transport traffic, no re-prime.
    ///
    /// Like states["content"], it does NOT come back as a finalized entry: the host is telling the
    /// element about an item it already has, so a host that also persists would write it twice.
    public func observeChatAppend(_ handler: @escaping (Any?) -> Void) -> AnyCancellable {
        $states.sink { handler($0["append"]) }
    }
}
