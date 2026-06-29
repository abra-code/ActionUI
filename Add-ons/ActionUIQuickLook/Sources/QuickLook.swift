// Add-ons/ActionUIQuickLook/Sources/QuickLook.swift
/*
 Sample JSON for QuickLook:
 {
   "type": "QuickLook",
   "id": 1,                  // Required: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "filePath": "/path/to/file.pdf",     // Optional: Absolute local path to preview; seeds the element value
     "previewStyle": "normal",            // Optional: macOS only; "normal" or "compact"; default "normal"; ignored on iOS/visionOS
     "showsChrome": false,                // Optional: Bool; show preview chrome - a nav bar (title + share/actions) on
                                          //           iOS, or a header (file name + share/open) on macOS; default false
     "valueChangeActionID": "ql.changed"  // Optional: Fired after the previewed item changes (a reload is dispatched)
   }
 }

 An embedded, in-process Quick Look preview pane, implemented as an ActionUI add-on (registered via
 ActionUIQuickLook.register()):
   macOS          - QLPreviewView (NSViewRepresentable).
   iOS / visionOS - QLPreviewController (UIViewControllerRepresentable, inline child).
   tvOS / watchOS - a graceful "not available" label.
 Quick Look previews local files only, so there is no remote "url" property - just "filePath" / the value.

 Observable state (via getElementValue / setElementValue):
   value (String)   Current source file path. Write a local file path to preview a different file;
                    valueChangeActionID fires after the preview reloads. "" means no source (shows nothing).

 Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity,
 cornerRadius, actionID, disabled, onAppearActionID, onDisappearActionID, etc.) are inherited from base View.

 Implementation note: conforms to ActionUI's public ActionUIViewConstruction contract. The type and its
 witnesses are internal to this module - an internal type conforming to a public protocol keeps internal
 witnesses; only ActionUIQuickLook.register() is public. Defined in a file that does not import Apple's
 QuickLook module, so the type name does not clash with it; the system QuickLook APIs are used in
 QuickLookRepresentable.swift.
 */

import SwiftUI
import ActionUI

struct QuickLook: ActionUIViewConstruction {

    // The element's runtime value is the source path / file-URL string.
    static var valueType: Any.Type = String.self

    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validated = properties

        for key in ["filePath", "valueChangeActionID"] {
            if let value = validated[key], !(value is String) {
                logger.log("QuickLook \(key) must be a String; ignoring", .warning)
                validated[key] = nil
            }
        }

        if let style = validated["previewStyle"] {
            if let styleString = style as? String {
                if !["normal", "compact"].contains(styleString) {
                    logger.log("QuickLook previewStyle '\(styleString)' invalid (expected normal|compact); ignoring", .warning)
                    validated["previewStyle"] = nil
                }
            } else {
                logger.log("QuickLook previewStyle must be a String; ignoring", .warning)
                validated["previewStyle"] = nil
            }
        }

        if let chrome = validated["showsChrome"], !(chrome is Bool) {
            logger.log("QuickLook showsChrome must be a Bool; ignoring", .warning)
            validated["showsChrome"] = nil
        }

        return validated
    }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        #if os(macOS)
        return QuickLookMacView(model: model, properties: properties, element: element,
                                windowUUID: windowUUID, logger: logger)
        #elseif os(iOS) || os(visionOS)
        return QLPreviewRepresentable(model: model, properties: properties, element: element,
                                      windowUUID: windowUUID, logger: logger)
        #else
        return SwiftUI.Label("Quick Look is not available on this platform", systemImage: "eye.slash")
        #endif
    }

    // Baseline View modifiers (frame, padding, background, ...) are applied by the registry.
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    // Value-primary element. The filePath JSON seed is resolved inside the representable (the
    // element's validated properties stay internal to ActionUI, so initialValue cannot read them).
    // Returns "" (not nil) when no value is set yet, so the non-Void String valueType has a
    // non-nil initial value - mirroring WebView, and avoiding the engine's "initial value not
    // provided" error. An empty string means "no source" (the representable shows nothing until the
    // host drives a path via setElementValue).
    static var initialValue: (ViewModel) -> Any? = { model in (model.value as? String) ?? "" }

    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }

    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil

    // Leaf view: no child containers accept runtime insertions.
    static var insertableContainers: [String: ContainerShape]? = nil
}
