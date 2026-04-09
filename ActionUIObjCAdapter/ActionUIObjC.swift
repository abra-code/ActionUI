//
//  ActionUIObjC.swift
//  ActionUIObjCAdapter
//

import ActionUI
import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Objective-C compatible logger protocol for bridging to ActionUILogger.
/// Design decision: Defined in adapter to avoid modifying core ActionUI, allowing Obj-C clients to implement logging without @objc in core protocol.
@objc public protocol ActionUIObjCLogger {
    @objc func logMessage(_ message: NSString, level: NSInteger)
}

/// Private bridge class to convert ActionUIObjCLogger to ActionUILogger.
private class ObjCLoggerBridge: ActionUILogger {
    let objCLogger: any ActionUIObjCLogger
    
    init(objCLogger: any ActionUIObjCLogger) {
        self.objCLogger = objCLogger
    }
    
    func log(_ message: String, _ level: LoggerLevel) {
        objCLogger.logMessage(message as NSString, level: level.rawValue)
    }
}

/// Modal presentation style for Objective-C. Maps to ActionUI.ModalStyle.
@objc public enum ActionUIObjCModalStyle: NSInteger {
    /// Standard sheet presentation.
    case sheet = 0
    /// Full-screen cover (iOS); falls back to sheet on macOS.
    case fullScreenCover = 1
}

/// Button role for Objective-C dialog buttons. Maps to SwiftUI.ButtonRole.
@objc public enum ActionUIObjCButtonRole: NSInteger {
    /// Default (no special role).
    case `default` = 0
    /// Cancel action.
    case cancel = 1
    /// Destructive action.
    case destructive = 2
}

/// An Objective-C-compatible dialog button descriptor. Maps to ActionUI.DialogButton.
@objc public class ActionUIObjCDialogButton: NSObject {
    @objc public let title: NSString
    @objc public let role: ActionUIObjCButtonRole
    @objc public let actionID: NSString?

    @objc public init(title: NSString, role: ActionUIObjCButtonRole, actionID: NSString?) {
        self.title = title
        self.role = role
        self.actionID = actionID
    }
}

/// Action handler block type for Objective-C with explicit parameter names.
/// Design decision: Named parameters improve readability in the generated Objective-C header.
/// No @objc attribute, as Swift automatically bridges this closure type to an Objective-C block in @objc methods.
public typealias ActionUIObjCActionHandlerBlock = (_ actionID: NSString, _ windowUUID: NSString, _ viewID: NSInteger, _ viewPartID: NSInteger, _ context: Any?) -> Void

/// Public entry point for the ActionUI Objective-C adapter, providing a simplified, static API to interact with the core ActionUI library.
/// Implemented in Swift with @objc annotations for Objective-C compatibility.
/// Design decision: Uses class methods (+) to mirror the static methods in ActionUISwift adapter.
/// Action handlers use Objective-C blocks, bridged to Swift closures for ActionUIModel.
/// Logger uses a bridged protocol to maintain modularity without altering core ActionUI.
/// All methods are @MainActor to align with ActionUIModel's concurrency model.
@objc public class ActionUIObjC: NSObject {
    @MainActor private static let model = ActionUIModel.shared
    
    /// Sets a custom logger for ActionUI to handle debugging and error reporting.
    /// - Parameter logger: A client-provided logger conforming to ActionUIObjCLogger.
    @MainActor @objc public class func setLogger(_ logger: any ActionUIObjCLogger) {
        model.logger = ObjCLoggerBridge(objCLogger: logger)
    }
    
    /// Sets the value of a view element identified by viewID in the specified window.
    /// Supports various value types as defined by the view's valueType in ActionUIRegistry.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - value: The value to set, matching the view's expected type.
    ///   - viewPartID: Optional part identifier (e.g., for multi-column tables; defaults to 0).
    @MainActor @objc public class func setElementValueWithWindowUUID(_ windowUUID: NSString, viewID: NSInteger, value: Any, viewPartID: NSInteger) {
        model.setElementValue(windowUUID: windowUUID as String, viewID: Int(viewID), value: value, viewPartID: Int(viewPartID))
    }
    
    /// Sets the value of a view element from a string representation, parsing it to the view's expected type.
    /// Supports ISO 8601 for Date, JSON for CLLocationCoordinate2D, and other type conversions per ActionUIModel.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - value: String representation of the value.
    ///   - viewPartID: Optional part identifier (e.g., for multi-column tables; defaults to 0).
    @MainActor @objc public class func setElementValueFromStringWithWindowUUID(_ windowUUID: NSString, viewID: NSInteger, value: NSString, viewPartID: NSInteger) {
        model.setElementValueFromString(windowUUID: windowUUID as String, viewID: Int(viewID), value: value as String, viewPartID: Int(viewPartID))
    }
    
    /// Gets the value of a view element identified by viewID in the specified window.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - viewPartID: Optional part identifier (e.g., for multi-column tables; defaults to 0).
    /// - Returns: The value of the view element, or nil if not found or invalid.
    @MainActor @objc public class func getElementValueWithWindowUUID(_ windowUUID: NSString, viewID: NSInteger, viewPartID: NSInteger) -> Any? {
        return model.getElementValue(windowUUID: windowUUID as String, viewID: Int(viewID), viewPartID: Int(viewPartID))
    }
    
    /// Gets the string representation of a view element's value.
    /// Uses type-specific formatting (e.g., ISO 8601 for Date, JSON for CLLocationCoordinate2D).
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - viewPartID: Optional part identifier (e.g., for multi-column tables; defaults to 0).
    /// - Returns: String representation of the value, or nil if not found or invalid.
    @MainActor @objc public class func getElementValueAsStringWithWindowUUID(_ windowUUID: NSString, viewID: NSInteger, viewPartID: NSInteger) -> NSString? {
        return model.getElementValueAsString(windowUUID: windowUUID as String, viewID: Int(viewID), viewPartID: Int(viewPartID)) as NSString?
    }
    
    /// Returns the current value for a single state key of a view element.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - key: The state key (e.g., "isLoading", "canGoBack").
    /// - Returns: The state value, or nil if the view or key is not found.
    @MainActor @objc public class func getElementStateWithWindowUUID(_ windowUUID: NSString, viewID: NSInteger, key: NSString) -> Any? {
        return model.getElementState(windowUUID: windowUUID as String, viewID: Int(viewID), key: key as String)
    }

    /// Returns the string representation of a single state value.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - key: The state key.
    /// - Returns: String representation, or nil if the view or key is not found.
    @MainActor @objc public class func getElementStateAsStringWithWindowUUID(_ windowUUID: NSString, viewID: NSInteger, key: NSString) -> NSString? {
        return model.getElementStateAsString(windowUUID: windowUUID as String, viewID: Int(viewID), key: key as String) as NSString?
    }

    /// Sets a single state key to a new value.
    /// Rejects the update (with an error log) if the new value's type differs from the existing value's type.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - key: The state key.
    ///   - value: The new value. Must match the type of the existing value if the key already exists.
    @MainActor @objc public class func setElementStateWithWindowUUID(_ windowUUID: NSString, viewID: NSInteger, key: NSString, value: Any) {
        model.setElementState(windowUUID: windowUUID as String, viewID: Int(viewID), key: key as String, value: value)
    }

    /// Sets a single state key by parsing a string into the type of the existing value.
    /// If the key does not yet exist the string is stored as-is.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - key: The state key.
    ///   - value: String representation of the new value.
    @MainActor @objc public class func setElementStateFromStringWithWindowUUID(_ windowUUID: NSString, viewID: NSInteger, key: NSString, value: NSString) {
        model.setElementStateFromString(windowUUID: windowUUID as String, viewID: Int(viewID), key: key as String, value: value as String)
    }

    /// Returns the number of columns defined for a table/list view element.
    /// Returns 0 for non-table elements or if the view is not found.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    /// - Returns: Number of columns, or 0 if the view is not a table or not found.
    @MainActor @objc public class func getElementColumnCountWithWindowUUID(_ windowUUID: NSString, viewID: NSInteger) -> NSInteger {
        return NSInteger(model.getElementColumnCount(windowUUID: windowUUID as String, viewID: Int(viewID)))
    }

    /// Returns all content rows for a table/list view element.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    /// - Returns: NSArray of NSArray<NSString*> rows, or nil if the view is not a table or not found.
    @MainActor @objc public class func getElementRowsWithWindowUUID(_ windowUUID: NSString, viewID: NSInteger) -> NSArray? {
        return model.getElementRows(windowUUID: windowUUID as String, viewID: Int(viewID)) as NSArray?
    }

    /// Clears all content rows from a table/list view element, preserving column definitions.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    @MainActor @objc public class func clearElementRowsWithWindowUUID(_ windowUUID: NSString, viewID: NSInteger) {
        model.clearElementRows(windowUUID: windowUUID as String, viewID: Int(viewID))
    }

    /// Replaces all content rows for a table/list view element.
    /// Clears the current selection if the selected row is no longer present.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - rows: NSArray of NSArray<NSString*> rows to set as the new content.
    @MainActor @objc public class func setElementRowsWithWindowUUID(_ windowUUID: NSString, viewID: NSInteger, rows: NSArray) {
        if let swiftRows = rows as? [[String]] {
            model.setElementRows(windowUUID: windowUUID as String, viewID: Int(viewID), rows: swiftRows)
        }
    }

    /// Appends rows to a table/list view element's existing content.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - rows: NSArray of NSArray<NSString*> rows to append.
    @MainActor @objc public class func appendElementRowsWithWindowUUID(_ windowUUID: NSString, viewID: NSInteger, rows: NSArray) {
        if let swiftRows = rows as? [[String]] {
            model.appendElementRows(windowUUID: windowUUID as String, viewID: Int(viewID), rows: swiftRows)
        }
    }

    /// Gets a structural property value for a view element by property name.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - propertyName: The property key (e.g., "columns", "widths", "disabled").
    /// - Returns: The property value, or nil if not found.
    @MainActor @objc public class func getElementPropertyWithWindowUUID(_ windowUUID: NSString, viewID: NSInteger, propertyName: NSString) -> Any? {
        return model.getElementProperty(windowUUID: windowUUID as String, viewID: Int(viewID), propertyName: propertyName as String)
    }

    /// Sets a structural property value for a view element by property name.
    /// The value is re-validated through the element's validateProperties function.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - propertyName: The property key (e.g., "columns", "widths", "disabled").
    ///   - value: The new property value.
    @MainActor @objc public class func setElementPropertyWithWindowUUID(_ windowUUID: NSString, viewID: NSInteger, propertyName: NSString, value: Any) {
        model.setElementProperty(windowUUID: windowUUID as String, viewID: Int(viewID), propertyName: propertyName as String, value: value)
    }

    /// Returns a dictionary mapping user-assigned (positive) view IDs to their ActionUI view type strings for a given window.
    /// Auto-assigned negative IDs and ID 0 are excluded.
    /// - Parameter windowUUID: Unique identifier for the window.
    /// - Returns: NSDictionary mapping NSNumber viewIDs to NSString ActionUI view types.
    @MainActor @objc public class func getElementInfoWithWindowUUID(_ windowUUID: NSString) -> NSDictionary {
        let info = model.getElementInfo(windowUUID: windowUUID as String)
        let nsDict = NSMutableDictionary(capacity: info.count)
        for (id, type) in info {
            nsDict[NSNumber(value: id)] = type as NSString
        }
        return nsDict
    }

    /// Registers an action handler for a specific actionID.
    /// - Parameters:
    ///   - actionID: Identifier for the action (e.g., "button.click").
    ///   - handler: Block to execute when the action is triggered, receiving actionID, windowUUID, viewID, viewPartID, and optional context.
    @MainActor @objc public class func registerActionHandlerForActionID(_ actionID: NSString, handler: @escaping ActionUIObjCActionHandlerBlock) {
        model.registerActionHandler(for: actionID as String) { swiftActionID, swiftWindowUUID, swiftViewID, swiftViewPartID, swiftContext in
            handler(swiftActionID as NSString, swiftWindowUUID as NSString, NSInteger(swiftViewID), NSInteger(swiftViewPartID), swiftContext)
        }
    }
    
    /// Unregisters an action handler for a specific actionID.
    /// - Parameter actionID: Identifier for the action to unregister.
    @MainActor @objc public class func unregisterActionHandlerForActionID(_ actionID: NSString) {
        model.unregisterActionHandler(for: actionID as String)
    }
    
    /// Sets a default action handler for unregistered actionIDs.
    /// - Parameter handler: Block to execute for unmatched actions, receiving actionID, windowUUID, viewID, viewPartID, and optional context.
    @MainActor @objc public class func setDefaultActionHandler(_ handler: @escaping ActionUIObjCActionHandlerBlock) {
        model.setDefaultActionHandler { swiftActionID, swiftWindowUUID, swiftViewID, swiftViewPartID, swiftContext in
            handler(swiftActionID as NSString, swiftWindowUUID as NSString, NSInteger(swiftViewID), NSInteger(swiftViewPartID), swiftContext)
        }
    }
    
    /// Removes the default action handler.
    @MainActor @objc public class func removeDefaultActionHandler() {
        model.removeDefaultActionHandler()
    }

    // MARK: - Modal Presentation

    /// Presents a window-level modal sheet or full-screen cover loaded from JSON/plist data.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - data: Encoded JSON or plist data describing the modal's view hierarchy.
    ///   - format: `"json"` or `"plist"`.
    ///   - style: `.sheet` or `.fullScreenCover`.
    ///   - onDismissActionID: Optional actionID fired when the modal is dismissed. Pass nil for none.
    ///   - error: On failure, set to a non-nil NSError describing the problem.
    /// - Returns: `YES` on success, `NO` on failure.
    @MainActor @objc public class func presentModalWithWindowUUID(_ windowUUID: NSString, data: NSData, format: NSString, style: ActionUIObjCModalStyle, onDismissActionID: NSString?, error: NSErrorPointer) -> Bool {
        let modalStyle: ActionUI.ModalStyle = style == .fullScreenCover ? .fullScreenCover : .sheet
        do {
            try model.presentModal(windowUUID: windowUUID as String, data: data as Data, format: format as String, style: modalStyle, onDismissActionID: onDismissActionID as String?)
            return true
        } catch let err as NSError {
            error?.pointee = err
            return false
        }
    }

    /// Dismisses the active window-level modal for the given window.
    /// - Parameter windowUUID: Unique identifier for the window.
    @MainActor @objc public class func dismissModalWithWindowUUID(_ windowUUID: NSString) {
        model.dismissModal(windowUUID: windowUUID as String)
    }

    /// Presents a window-level alert dialog.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - title: Alert title.
    ///   - message: Optional alert message. Pass nil to omit.
    ///   - buttons: Optional NSArray of `ActionUIObjCDialogButton`. Pass nil for a single default OK button.
    @MainActor @objc public class func presentAlertWithWindowUUID(_ windowUUID: NSString, title: NSString, message: NSString?, buttons: NSArray?) {
        let swiftButtons = dialogButtons(from: buttons)
        if let swiftButtons {
            model.presentAlert(windowUUID: windowUUID as String, title: title as String, message: message as String?, buttons: swiftButtons)
        } else {
            model.presentAlert(windowUUID: windowUUID as String, title: title as String, message: message as String?)
        }
    }

    /// Presents a window-level confirmation dialog (action sheet style on iOS).
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - title: Dialog title.
    ///   - message: Optional dialog message. Pass nil to omit.
    ///   - buttons: NSArray of `ActionUIObjCDialogButton` defining the available choices.
    @MainActor @objc public class func presentConfirmationDialogWithWindowUUID(_ windowUUID: NSString, title: NSString, message: NSString?, buttons: NSArray) {
        let swiftButtons = dialogButtons(from: buttons) ?? []
        model.presentConfirmationDialog(windowUUID: windowUUID as String, title: title as String, message: message as String?, buttons: swiftButtons)
    }

    /// Dismisses the active window-level alert or confirmation dialog for the given window.
    /// - Parameter windowUUID: Unique identifier for the window.
    @MainActor @objc public class func dismissDialogWithWindowUUID(_ windowUUID: NSString) {
        model.dismissDialog(windowUUID: windowUUID as String)
    }

    /// Converts an NSArray of ActionUIObjCDialogButton to [ActionUI.DialogButton]. Returns nil if array is nil or empty.
    private class func dialogButtons(from array: NSArray?) -> [ActionUI.DialogButton]? {
        guard let array, array.count > 0 else { return nil }
        return array.compactMap { element -> ActionUI.DialogButton? in
            guard let btn = element as? ActionUIObjCDialogButton else { return nil }
            let role: SwiftUI.ButtonRole? = switch btn.role {
                case .cancel: .cancel
                case .destructive: .destructive
                default: nil
            }
            return ActionUI.DialogButton(title: btn.title as String, role: role, actionID: btn.actionID as String?)
        }
    }

    #if canImport(AppKit)
    /// Loads an NSView hosting a SwiftUI view from a JSON or plist description at the given URL (local or remote).
    /// Available only on macOS.
    /// - Parameters:
    ///   - url: The URL to the JSON or plist description file (file:// for local, http:// or https:// for remote).
    ///   - windowUUID: Unique identifier for the window.
    ///   - isContentView: If true, loads as the root view of the window; if false, loads as a subview without overwriting the root element.
    /// - Returns: An NSView (specifically, NSHostingView) with the loaded SwiftUI view embedded. If the URL or data is invalid, the view displays an error message.
    /// Design decision: Returns NSView for Obj-C compatibility, as NSHostingView<any SwiftUI.View> is not bridgeable to Objective-C. Non-optional return reflects guaranteed view creation, with errors surfaced as view content.
    @MainActor @objc public class func loadViewWithURL(_ url: NSURL, windowUUID: NSString, isContentView: Bool) -> NSView {
        let swiftView = loadActionUIView(from: url as URL, windowUUID: windowUUID as String, isContentView: isContentView)
        let hostingView = NSHostingView(rootView: AnyView(swiftView))
        hostingView.autoresizingMask = [.width, .height]
		
		// clients can use `hostingView.fittingSize` to set the window size
        
        return hostingView
    }
    #endif
    
    #if canImport(AppKit)
    /// Loads an NSViewController hosting a SwiftUI view from a JSON or plist description at the given URL (local or remote).
    /// - Parameters:
    ///   - url: The URL to the JSON or plist description file (file:// for local, http:// or https:// for remote).
    ///   - windowUUID: Unique identifier for the window.
    ///   - isContentView: If true, loads as the root view of the window; if false, loads as a subview without overwriting the root element.
    /// - Returns: An NSViewController (specifically, NSHostingController) with the loaded SwiftUI view embedded as its root view. If the URL or data is invalid, the view displays an error message.
    /// Design decision: Returns NSViewController for Obj-C compatibility; wraps the view in an NSHostingController for macOS integration. Non-optional return reflects guaranteed controller creation, with errors surfaced as view content.
    @MainActor @objc public class func loadHostingControllerWithURL(_ url: NSURL, windowUUID: NSString, isContentView: Bool) -> NSViewController {
        let swiftView = loadActionUIView(from: url as URL, windowUUID: windowUUID as String, isContentView: isContentView)
        let hostingController = NSHostingController(rootView: AnyView(swiftView))
        hostingController.view.autoresizingMask = [.width, .height]
        
        // clients can use `hostingController.view.fittingSize` to adjust
        // the size of the window hosting this view as a main content view

        return hostingController
    }
    #endif
    
    #if canImport(UIKit)
    /// Loads a UIViewController hosting a SwiftUI view from a JSON or plist description at the given URL (local or remote).
    /// - Parameters:
    ///   - url: The URL to the JSON or plist description file (file:// for local, http:// or https:// for remote).
    ///   - windowUUID: Unique identifier for the window.
    ///   - isContentView: If true, loads as the root view of the window; if false, loads as a subview without overwriting the root element.
    /// - Returns: A UIViewController (specifically, UIHostingController) with the loaded SwiftUI view embedded as its root view. If the URL or data is invalid, the view displays an error message.
    /// Design decision: Returns UIViewController for Obj-C compatibility; wraps the view in a UIHostingController for UIKit integration. Non-optional return reflects guaranteed controller creation, with errors surfaced as view content.
    @MainActor @objc public class func loadHostingControllerWithURL(_ url: NSURL, windowUUID: NSString, isContentView: Bool) -> UIViewController {
        let swiftView = loadActionUIView(from: url as URL, windowUUID: windowUUID as String, isContentView: isContentView)
        let hostingController = UIHostingController(rootView: AnyView(swiftView))
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return hostingController
    }
    #endif
    
    /// Internal helper to load the SwiftUI view, used by both loadView and loadHostingController.
    /// Not exposed to Obj-C; bridges NSURL to URL and handles local/remote loading.
    /// Design decision: Mirrors ActionUISwift.loadView for consistency, using FileLoadableView or RemoteLoadableView based on URL scheme. Always returns a valid view, with errors displayed as view content.
    @MainActor private class func loadActionUIView(from url: URL, windowUUID: String, isContentView: Bool) -> any SwiftUI.View {
        let logger = model.logger
        if url.scheme == "file" {
            return ActionUI.FileLoadableView(fileURL: url, windowUUID: windowUUID, isContentView: isContentView, logger: logger)
        } else {
            return ActionUI.RemoteLoadableView(url: url, windowUUID: windowUUID, isContentView: isContentView, logger: logger)
        }
    }
}
