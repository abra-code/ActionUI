// Sources/Runtime/ContentSizeLimits+WinUI.swift
/*
 The size limits of a window's content on Windows, the counterpart of Apple's (ActionUI/Common/
 ContentSizeLimits.swift) and Linux's (ActionUIAdwaita/Sources/Runtime/ContentSizeLimits+Adwaita.swift),
 which the remote server's actionui.contentSizeLimits answers with. Not measured on Windows yet: always
 nil, which the method answers as null, as Linux does for a window that is not on screen.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The size limits of a window's content. Apple's has CGSize members; these have the same names, so
/// code reading `limits.minSize.width` builds on every platform.
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
    /// The size limits of the content of the window showing `windowUUID`: nil on Windows for now.
    public func contentSizeLimits(windowUUID: String) -> ContentSizeLimits? {
        return nil
    }
}
