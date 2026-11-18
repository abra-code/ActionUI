// Sources/Interop/WinUIError.swift
/*
 A failed call into the WinUI shim. The shim's functions return false on failure and leave a
 message for the calling thread (actionUIWinUICopyLastError); WinUIError.last reads it.
*/

import CWinUI

package struct WinUIError: Error, CustomStringConvertible {
    /// What was being done, for the reader: "creating a window".
    package let operation: String
    /// The shim's message.
    package let message: String

    package var description: String {
        "\(operation) failed: \(message)"
    }

    /// The error for `operation`, with the calling thread's last shim message.
    package static func last(_ operation: String) -> WinUIError {
        var buffer = [CChar](repeating: 0, count: 1024)
        let copied = buffer.withUnsafeMutableBufferPointer { pointer in
            actionUIWinUICopyLastError(pointer.baseAddress, pointer.count)
        }
        let message = copied ? String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) : ""
        return WinUIError(operation: operation, message: message.isEmpty ? "(no message)" : message)
    }
}
