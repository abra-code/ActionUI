// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// Messages+FoundationEssentials.swift - the messages that depend on Foundation, where only
// FoundationEssentials is used (Linux, Windows). Messages+Foundation.swift has them with Apple's
// Foundation.

#if canImport(FoundationEssentials)

import FoundationEssentials

/// An error as a person reads it. Foundation's Error.localizedDescription is not in
/// FoundationEssentials.
func describe(_ error: Error) -> String {
    // A read failure is a CocoaError around the system's error.
    if let cause = (error as? CocoaError)?.userInfo["NSUnderlyingError"] as? POSIXError {
        return errorText(cause.code.rawValue)
    }
    return String(describing: error)
}

/// Why a file is not JSON.
func invalidJSONReason(_ error: Error) -> String {
    describe(error)
}

let schemasNotFoundMessage = "[ERROR] Schemas directory not found.\nEnsure share/actionui/schemas is next to the bin folder of this tool, or pass --schemas <dir>."

#endif
