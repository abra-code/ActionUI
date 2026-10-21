// Core/Common/ActionUIError.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A failure ActionUI reports with a message alone: a description that cannot be loaded, a window
/// that does not exist. Its text is the message, whether a host reads `localizedDescription` (on
/// Apple: Common/ActionUIError+Foundation.swift) or interpolates the error.
public struct ActionUIError: Error, Sendable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}
