// ActionUICAdapter/ActionUIC+Apple.swift
//
//  The C function that hands a host a native view: Apple only. The rest of the C interface,
//  which works with values and JSON text, is in ActionUIC.swift.
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
