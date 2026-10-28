// ActionUICAdapter/ActionUIC+Apple.swift
//
//  The C functions that hand a host a native view or measure SwiftUI content: Apple only. The
//  rest of the C interface, which works with values and JSON text, is in ActionUIC.swift.
//  Also the Apple side of hostNative (the Linux side is ActionUIC+Linux.swift).
//

import Foundation
import ActionUI
import SwiftUI

#if SWIFT_PACKAGE
import ActionUICAdapterHeaders
#endif

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Host values

/// A value a host stored, made Swift-native for ActionUIJSON: Objective-C and Swift hosts on Apple
/// can store Foundation objects (NSNumber, NSString, NSNull) as element values.
func hostNative(_ value: Any) -> Any {
    FoundationBridge.native(value)
}

// MARK: - UI Loading


@c
public func actionUILoadHostingControllerFromURL(
    _ urlString: UnsafePointer<CChar>,
    _ windowUUID: UnsafePointer<CChar>,
    _ isContentView: CBool
) -> UnsafeMutableRawPointer? {
    clearError()
    
    let swiftURLString = String(cString: urlString)
    let swiftWindowUUID = String(cString: windowUUID)
    
    guard let url = URL(string: swiftURLString) else {
        setError("Invalid URL: \(swiftURLString)")
        return nil
    }
    
    
    return runOnMainActorSync {
        let logger = ActionUIModel.shared.logger
        var view: any SwiftUI.View

        if url.scheme == "file" {
            view = ActionUI.FileLoadableView(fileURL: url, windowUUID: swiftWindowUUID, isContentView: isContentView, logger: logger)
        } else {
            view = ActionUI.RemoteLoadableView(url: url, windowUUID: swiftWindowUUID, isContentView: isContentView, logger: logger)
        }
        
        #if canImport(AppKit)
        let hostingController = NSHostingController(rootView: AnyView(view))
        hostingController.view.autoresizingMask = [.width, .height]
        return Unmanaged.passRetained(hostingController).toOpaque()
        #elseif canImport(UIKit)
        let hostingController = UIHostingController(rootView: AnyView(view))
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return Unmanaged.passRetained(hostingController.view!).toOpaque()
        #else
        setError("Unsupported platform")
        return nil
        #endif
    }
}

// MARK: - Content Size Limits

/// Returns the size limits of a loaded window's root element content (macOS only):
/// the minimum is what the SwiftUI content reports for a zero size proposal, the
/// maximum for an infinite one. Flexible axes report a very large maximum; content
/// with a fixed root frame reports min == max, which lets a client make its window
/// non-user-resizable. Measures the bare root element, bypassing the window-level
/// modal/toast wrapper, which always expands to fill. Call after
/// actionUILoadHostingControllerFromURL has loaded the document.
/// Out parameters may be NULL to skip a component. Returns false (with an error set)
/// when the window is unknown or on non-macOS platforms.
@c
public func actionUIGetContentSizeLimits(
    _ windowUUID: UnsafePointer<CChar>,
    _ outMinWidth: UnsafeMutablePointer<Double>?,
    _ outMinHeight: UnsafeMutablePointer<Double>?,
    _ outMaxWidth: UnsafeMutablePointer<Double>?,
    _ outMaxHeight: UnsafeMutablePointer<Double>?
) -> CBool {
    clearError()

    #if canImport(AppKit)
    let swiftWindowUUID = String(cString: windowUUID)

    let limits = runOnMainActorSync {
        ActionUIModel.shared.contentSizeLimits(windowUUID: swiftWindowUUID)
    }
    guard let limits else {
        setError("Unknown windowUUID or no root element loaded: \(swiftWindowUUID)")
        return false
    }
    outMinWidth?.pointee = Double(limits.minSize.width)
    outMinHeight?.pointee = Double(limits.minSize.height)
    outMaxWidth?.pointee = Double(limits.maxSize.width)
    outMaxHeight?.pointee = Double(limits.maxSize.height)
    return true
    #else
    setError("Content size limits are only available on macOS")
    return false
    #endif
}

