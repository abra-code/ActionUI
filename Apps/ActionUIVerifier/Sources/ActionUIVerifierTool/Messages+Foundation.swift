// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// Messages+Foundation.swift - the messages that depend on Foundation, with Apple's Foundation.
// Messages+FoundationEssentials.swift has them where only FoundationEssentials is used (Linux,
// Windows).

#if !canImport(FoundationEssentials)

import Foundation

/// An error as a person reads it.
func describe(_ error: Error) -> String {
    error.localizedDescription
}

/// Why a file is not JSON: JSONSerialization's own explanation when it gives one.
func invalidJSONReason(_ error: Error) -> String {
    (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? describe(error)
}

let schemasNotFoundMessage = "[ERROR] Schemas directory not found in the verifier's resource bundle.\nEnsure ActionUI_ActionUIVerifier.bundle is next to this tool, or pass --schemas <dir>."

#endif
