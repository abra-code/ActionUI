// ActionUICoreCheck/ContentSizeLimits+CoreCheck.swift
/*
 The renderer's content size limits for the Core-only check package (Package.swift, coreCheckPackage),
 which the remote server's actionui.contentSizeLimits asks for: no renderer measures anything there, so
 there are none (null on the wire). Each real renderer provides its own (ActionUI/Common/
 ContentSizeLimits.swift, ActionUIAdwaita/Sources/Runtime/ContentSizeLimits+Adwaita.swift,
 ActionUIWinUI/Sources/Runtime/ContentSizeLimits+WinUI.swift).
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The size limits of a window's content, with the members the other renderers' have.
public struct ContentSizeLimits: Sendable, Equatable {
    public struct Size: Sendable, Equatable {
        public let width: Double
        public let height: Double
    }

    public let minSize: Size
    public let maxSize: Size
}

@MainActor
extension ActionUIModel {
    /// No renderer, no measurement: always nil.
    public func contentSizeLimits(windowUUID: String) -> ContentSizeLimits? {
        return nil
    }
}
