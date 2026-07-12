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
}
