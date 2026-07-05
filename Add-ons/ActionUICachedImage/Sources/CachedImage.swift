// Add-ons/ActionUICachedImage/Sources/CachedImage.swift
/*
 Sample JSON for CachedImage:
 {
   "type": "CachedImage",
   "id": 1,                  // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "url": "https://example.com/photo.jpg", // Optional: web / file / data URL of the image; seeds the element
                                             //           value. Nil or invalid shows the placeholder.
     "intrinsicSize": { "width": 1024, "height": 768 }, // Optional: the source's natural size, if known ahead of
                                             //           load (e.g. server metadata). Reserves the exact box up
                                             //           front so the image hydrates with ZERO reflow.
     "contentMode": "fill",                  // Optional: "fit" or "fill" - how the image fills the reserved box;
                                             //           default "fill" (CachedImage's own default).
     "maxPixelWidth": 840,                   // Optional: cap the DECODED width in pixels (downscaled off-main) to
                                             //           bound memory for large sources; omit for natural resolution.
     "cornerRadius": 12                      // Optional: Number; rounds the image (a continuous-corner clip applied
                                             //           by CachedImage itself, so it rounds the visible image).
   }
   // Note: "cornerRadius" is the standard View property name, but this element rounds the image itself (the baseline
   // cornerRadius modifier would round only the transparent outer frame, not the aspect-fit image). Sizing uses
   // baseline "frame". Other baseline View properties (padding, hidden, background, frame, opacity, actionID,
   // onAppearActionID, onDisappearActionID, etc.) are inherited from base View.
 }

 A cached, off-main image view backed by AsyncImageCache's ImageStore, implemented as an ActionUI
 add-on (registered via ActionUICachedImage.register()):
   macOS / iOS / visionOS - AsyncImageCache.CachedImage (a SwiftUI View; AsyncImageCache's platforms).
 Bytes are fetched / decoded / downscaled OFF the main thread and served from a two-tier (memory +
 on-disk) cache; the natural pixel size is known up front (persisted as a file extended attribute) so
 layout reserves the exact box with no reflow on hydration, even across relaunch.

 Observable state (via getElementValue / setElementValue):
   value (String)   Current image URL string. Write a new URL to load a different image; "" or nil
                    shows the placeholder.

 Implementation note: this element type is itself named `CachedImage` (so its JSON token is
 "CachedImage"), which shadows the AsyncImageCache view of the same name inside this file. The wrapped
 view is therefore reached with the module-qualified `AsyncImageCache.CachedImage`. The type and its
 witnesses are internal to this module - an internal type conforming to a public protocol keeps
 internal witnesses; only ActionUICachedImage.register() is public.
 */

import SwiftUI
import ActionUI
import AsyncImageCache

struct CachedImage: ActionUIViewConstruction {

    // The element's runtime value is the image URL string (like the core AsyncImage element).
    static var valueType: Any.Type = String.self

    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validated = properties

        if let url = validated["url"], !(url is String) {
            logger.log("CachedImage url must be a String; ignoring", .warning)
            validated["url"] = nil
        }

        if let mode = validated["contentMode"] {
            if let modeString = mode as? String {
                if !["fit", "fill"].contains(modeString) {
                    logger.log("CachedImage contentMode '\(modeString)' invalid (expected fit|fill); ignoring", .warning)
                    validated["contentMode"] = nil
                }
            } else {
                logger.log("CachedImage contentMode must be a String; ignoring", .warning)
                validated["contentMode"] = nil
            }
        }

        if let width = validated["maxPixelWidth"], numericCGFloat(width) == nil {
            logger.log("CachedImage maxPixelWidth must be a number; ignoring", .warning)
            validated["maxPixelWidth"] = nil
        }

        if let size = validated["intrinsicSize"], intrinsicSize(from: size) == nil {
            logger.log("CachedImage intrinsicSize must be an object with positive numeric width and height; ignoring", .warning)
            validated["intrinsicSize"] = nil
        }

        // cornerRadius: baseline View.validateProperties (run before this) has already validated it as
        // numeric. Move it out of the dict the registry hands to the baseline modifier and stash it for
        // buildView, so CachedImage applies the rounding NATIVELY (a continuous clip right around the
        // image). The baseline "cornerRadius" modifier cannot round the image here: CachedImage renders
        // the image as an aspect-fit overlay on a Color.clear box, so under a filling frame the baseline
        // clip rounds the transparent outer frame while the centered image keeps square corners.
        if let radius = validated["cornerRadius"] {
            validated[cornerRadiusStashKey] = radius
            validated["cornerRadius"] = nil
        }

        return validated
    }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        // Effective source: the runtime value (setElementValue) wins, else the "url" JSON property.
        // buildView receives the validated `properties` directly, whereas initialValue cannot read the
        // "url" seed (model.validatedProperties is internal to ActionUI), so the seed is resolved here -
        // the same split the ActionUIQuickLook add-on uses for its filePath seed.
        let runtime = (model.value as? String).flatMap { $0.isEmpty ? nil : $0 }
        let urlString = runtime ?? (properties["url"] as? String)
        // A non-empty, parseable URL string, else nil (CachedImage renders its placeholder for nil).
        let url = urlString.flatMap { $0.isEmpty ? nil : URL(string: $0) }
        let intrinsic = intrinsicSize(from: properties["intrinsicSize"])
        let contentMode: ContentMode = (properties["contentMode"] as? String == "fit") ? .fit : .fill
        let maxPixelWidth = numericCGFloat(properties["maxPixelWidth"])

        // cornerRadius rounds the image via CachedImage's own (continuous-corner) clip, which sits right
        // around the image; validateProperties stashed it here (see cornerRadiusStashKey) so the baseline
        // modifier does not also apply an ineffective outer clip.
        let cornerRadius = numericCGFloat(properties[cornerRadiusStashKey]) ?? 0
        return AsyncImageCache.CachedImage(url: url,
                                           intrinsicSize: intrinsic,
                                           cornerRadius: cornerRadius,
                                           contentMode: contentMode,
                                           maxPixelWidth: maxPixelWidth)
    }

    // Baseline View modifiers (frame, padding, background, opacity, ...) are applied by the registry.
    // (cornerRadius is the exception - this element consumes it and rounds the image itself; see above.)
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    // Value-primary element. The "url" JSON seed is resolved inside buildView (an external add-on
    // cannot read model.validatedProperties - it is internal to ActionUI), so initialValue only
    // reflects the runtime value. Returns "" (not nil) when no value is set yet, so the non-Void
    // String valueType has a non-nil initial value - mirroring ActionUIQuickLook and avoiding the
    // engine's "initial value not provided" error. An empty string means "no runtime source", and
    // buildView then falls back to the "url" property.
    static var initialValue: (ViewModel) -> Any? = { model in (model.value as? String) ?? "" }

    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }

    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil

    // Leaf view: no child containers accept runtime insertions.
    static var insertableContainers: [String: ContainerShape]? = nil
}

// MARK: - Property coercion (this module cannot see ActionUI's internal Dictionary+Numeric helper)

/// Coerces a JSON-decoded numeric value to CGFloat, matching the numeric types ActionUI's decoder
/// produces (Int / Double / Float / CGFloat). Returns nil for non-numeric values (Bool does not
/// cast to Int/Double via `as?`, so a JSON boolean is correctly rejected).
private func numericCGFloat(_ any: Any?) -> CGFloat? {
    switch any {
    case let value as CGFloat: return value
    case let value as Double: return CGFloat(value)
    case let value as Int: return CGFloat(value)
    case let value as Float: return CGFloat(value)
    default: return nil
    }
}

/// Private key under which validateProperties stashes the (baseline-validated) cornerRadius, so buildView
/// can pass it to CachedImage's native corner clip while the baseline "cornerRadius" modifier - which
/// would round only the transparent outer frame, not the image - does not also apply.
private let cornerRadiusStashKey = "__cachedImageCornerRadius"

/// Parses an `{ "width": Number, "height": Number }` object into a CGSize; nil if the shape or either
/// component is missing or non-numeric. Zero / negative dimensions are rejected - an intrinsic size
/// must be positive to reserve a box (and AsyncImageCache divides by it to derive an aspect ratio).
private func intrinsicSize(from any: Any?) -> CGSize? {
    guard let dict = any as? [String: Any],
          let width = numericCGFloat(dict["width"]),
          let height = numericCGFloat(dict["height"]),
          width > 0, height > 0 else {
        return nil
    }
    return CGSize(width: width, height: height)
}
