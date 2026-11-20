// Core/Common/ActionUIError.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A failure ActionUI reports with a message alone: a description that cannot be loaded, a window
/// that does not exist. Its text is the message, whether a host reads `localizedDescription` (on
/// Apple: the LocalizedError conformance below) or interpolates the error.
public struct ActionUIError: Error, Sendable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

#if !canImport(FoundationEssentials)
/// On Apple, an ActionUIError's localizedDescription is its message, as it was for the NSError it
/// replaces. LocalizedError is Foundation's, which Core imports only on Apple.
///
/// Here and not in a file of its own: a host links ActionUI as a static library, and the linker
/// drops an object file nothing refers to by name. A conformance alone is found only by a cast at
/// run time, so in a file of its own it was missing from the Xcode tests, the test apps and the Node prebuilds.
extension ActionUIError: LocalizedError {
    public var errorDescription: String? { message }
}
#endif
