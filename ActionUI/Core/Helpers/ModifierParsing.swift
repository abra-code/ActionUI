// Core/Helpers/ModifierParsing.swift
/*
 ModifierParsing: the rules for the base modifiers whose values are structured (frame, offset,
 scale, shadow, border, animation, transition, keyboard shortcut, clip shape, padding, column
 width). Each function turns one raw property value, as JSON decoding or setElementProperty left
 it, into a portable description, or nil when the value is not usable. BaseModifiers calls these;
 renderers never parse these keys themselves.

 Portable on purpose: Foundation types only, so every renderer shares the same rules.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

enum ModifierParsing {

    // MARK: - Padding

    /// A number, the string "default" (any case), or a dictionary of edges. A dictionary must have
    /// at least one numeric edge; edges that are missing or not numbers are 0.
    static func padding(_ value: Any?) -> BaseModifiers.Padding? {
        if let dict = value as? [String: Any] {
            let top = dict.double(forKey: "top")
            let leading = dict.double(forKey: "leading")
            let bottom = dict.double(forKey: "bottom")
            let trailing = dict.double(forKey: "trailing")
            guard top != nil || leading != nil || bottom != nil || trailing != nil else {
                return nil
            }
            return .edges(top: top ?? 0, leading: leading ?? 0, bottom: bottom ?? 0, trailing: trailing ?? 0)
        }
        if let number = JSONNumber.double(value) {
            return .uniform(number)
        }
        if let text = value as? String, text.lowercased() == "default" {
            return .system
        }
        return nil
    }

    // MARK: - Frame

    private static let fixedFrameKeys = ["width", "height"]
    private static let flexibleFrameKeys = ["minWidth", "idealWidth", "maxWidth", "minHeight", "idealHeight", "maxHeight"]

    /// A dictionary in one of two forms: fixed (width, height) or flexible (min, ideal and max per
    /// axis), each with an optional alignment. nil when it is not a dictionary, when it mixes keys
    /// of both forms, or when any size key present is not a number. An unknown alignment is
    /// dropped (the renderer centers). A dictionary with neither form's keys is a frame that only
    /// aligns.
    static func frame(_ value: Any?) -> BaseModifiers.Frame? {
        guard let dict = value as? [String: Any] else {
            return nil
        }
        let hasFixed = fixedFrameKeys.contains { dict[$0] != nil }
        let hasFlexible = flexibleFrameKeys.contains { dict[$0] != nil }
        if hasFixed && hasFlexible {
            return nil
        }
        for key in fixedFrameKeys + flexibleFrameKeys where dict[key] != nil && dict.double(forKey: key) == nil {
            return nil
        }
        return BaseModifiers.Frame(
            width: dict.double(forKey: "width"),
            height: dict.double(forKey: "height"),
            minWidth: dict.double(forKey: "minWidth"),
            idealWidth: dict.double(forKey: "idealWidth"),
            maxWidth: dict.double(forKey: "maxWidth"),
            minHeight: dict.double(forKey: "minHeight"),
            idealHeight: dict.double(forKey: "idealHeight"),
            maxHeight: dict.double(forKey: "maxHeight"),
            alignment: (dict["alignment"] as? String).flatMap(BaseModifiers.AlignmentName.init(rawValue:))
        )
    }

    // MARK: - Offset, scale, rotation

    /// A dictionary with numeric x and y (either may be missing: 0). nil when it is not a
    /// dictionary, when it is empty, or when x or y is present but not a number.
    static func offset(_ value: Any?) -> BaseModifiers.Offset? {
        guard let dict = value as? [String: Any], !dict.isEmpty else {
            return nil
        }
        let x = dict.double(forKey: "x")
        let y = dict.double(forKey: "y")
        if (dict["x"] != nil && x == nil) || (dict["y"] != nil && y == nil) || (x == nil && y == nil) {
            return nil
        }
        return BaseModifiers.Offset(x: x ?? 0, y: y ?? 0)
    }

    /// A number (the same factor on both axes, around the center), or a dictionary with numeric x
    /// and y (missing: 1) and an anchor. nil when a present x or y is not a number, or when the
    /// dictionary has none of x, y and a valid anchor. An unknown anchor is dropped (center).
    static func scale(_ value: Any?) -> BaseModifiers.Scale? {
        if let dict = value as? [String: Any] {
            let x = dict.double(forKey: "x")
            let y = dict.double(forKey: "y")
            if (dict["x"] != nil && x == nil) || (dict["y"] != nil && y == nil) {
                return nil
            }
            let anchor = (dict["anchor"] as? String).flatMap(BaseModifiers.AlignmentName.init(rawValue:))
            if x == nil && y == nil && anchor == nil {
                return nil
            }
            return BaseModifiers.Scale(x: x ?? 1, y: y ?? 1, anchor: anchor ?? .center)
        }
        if let factor = JSONNumber.double(value) {
            return BaseModifiers.Scale(x: factor, y: factor, anchor: .center)
        }
        return nil
    }

    // MARK: - Shadow, border

    /// A dictionary with an optional color (String) and numeric radius, x and y (missing: 0). nil
    /// when it is not a dictionary, when it is empty, or when a present field has the wrong type.
    static func shadow(_ value: Any?) -> BaseModifiers.Shadow? {
        guard let dict = value as? [String: Any], !dict.isEmpty else {
            return nil
        }
        let color = dict["color"] as? String
        let radius = dict.double(forKey: "radius")
        let x = dict.double(forKey: "x")
        let y = dict.double(forKey: "y")
        if (dict["color"] != nil && color == nil) || (dict["radius"] != nil && radius == nil)
            || (dict["x"] != nil && x == nil) || (dict["y"] != nil && y == nil) {
            return nil
        }
        if color == nil && radius == nil && x == nil && y == nil {
            return nil
        }
        return BaseModifiers.Shadow(color: color, radius: radius ?? 0, x: x ?? 0, y: y ?? 0)
    }

    /// A dictionary with an optional color (String) and numeric width (missing: 1). An empty
    /// dictionary is a default border. nil when it is not a dictionary, or when a present field
    /// has the wrong type.
    static func border(_ value: Any?) -> BaseModifiers.Border? {
        guard let dict = value as? [String: Any] else {
            return nil
        }
        let color = dict["color"] as? String
        let width = dict.double(forKey: "width")
        if (dict["color"] != nil && color == nil) || (dict["width"] != nil && width == nil) {
            return nil
        }
        return BaseModifiers.Border(color: color, width: width ?? 1)
    }

    // MARK: - Clip shape

    /// A shape name ("rectangle", "circle", "capsule", "ellipse"), or a dictionary with type
    /// "roundedRectangle" and either cornerRadius or both cornerRadiusX and cornerRadiusY. nil for
    /// anything else.
    static func clipShape(_ value: Any?) -> BaseModifiers.ClipShape? {
        if let name = value as? String {
            switch name {
            case "rectangle": return .rectangle
            case "circle":    return .circle
            case "capsule":   return .capsule
            case "ellipse":   return .ellipse
            default:          return nil
            }
        }
        guard let dict = value as? [String: Any], dict["type"] as? String == "roundedRectangle" else {
            return nil
        }
        if let radius = dict.double(forKey: "cornerRadius") {
            return .roundedRectangle(radiusX: radius, radiusY: radius)
        }
        if let rx = dict.double(forKey: "cornerRadiusX"), let ry = dict.double(forKey: "cornerRadiusY") {
            return .roundedRectangle(radiusX: rx, radiusY: ry)
        }
        return nil
    }

    // MARK: - Animation, transition

    /// A curve name, or a dictionary with a curve (required) and optional duration (> 0), delay
    /// (>= 0), speed (> 0) and value (String: the property or state to watch). Fields outside
    /// their range are dropped. nil without a valid curve.
    static func animation(_ value: Any?) -> BaseModifiers.Animation? {
        if let name = value as? String {
            return BaseModifiers.Animation.Curve(rawValue: name).map { BaseModifiers.Animation(curve: $0) }
        }
        guard let dict = value as? [String: Any],
              let curve = (dict["curve"] as? String).flatMap(BaseModifiers.Animation.Curve.init(rawValue:)) else {
            return nil
        }
        var animation = BaseModifiers.Animation(curve: curve)
        if let duration = dict.double(forKey: "duration"), duration > 0 {
            animation.duration = duration
        }
        if let delay = dict.double(forKey: "delay"), delay >= 0 {
            animation.delay = delay
        }
        if let speed = dict.double(forKey: "speed"), speed > 0 {
            animation.speed = speed
        }
        animation.watchedValue = dict["value"] as? String
        return animation
    }

    /// A transition type name (shorthand), a dictionary with a "type" and its parameters, or an
    /// array of these (combined; invalid entries are skipped). "asymmetric" takes insertion and
    /// removal, each in any of these forms; a missing or invalid one is identity. nil when nothing
    /// valid remains.
    static func transition(_ value: Any?) -> BaseModifiers.Transition? {
        if let array = value as? [Any] {
            let parts = array.compactMap { transition($0) }
            return parts.isEmpty ? nil : .combined(parts)
        }
        let dict: [String: Any]
        if let name = value as? String {
            dict = ["type": name]
        } else if let given = value as? [String: Any] {
            dict = given
        } else {
            return nil
        }
        switch dict["type"] as? String {
        case "identity":
            return .identity
        case "opacity":
            return .opacity
        case "slide":
            return .slide
        case "scale":
            let anchor = (dict["anchor"] as? String).flatMap(BaseModifiers.AlignmentName.init(rawValue:)) ?? .center
            return .scale(factor: dict.double(forKey: "scale"), anchor: anchor)
        case "move":
            let edge = (dict["edge"] as? String).flatMap(BaseModifiers.EdgeName.init(rawValue:)) ?? .bottom
            return .move(edge: edge)
        case "offset":
            return .offset(x: dict.double(forKey: "x") ?? 0, y: dict.double(forKey: "y") ?? 0)
        case "asymmetric":
            return .asymmetric(
                insertion: transition(dict["insertion"]) ?? .identity,
                removal: transition(dict["removal"]) ?? .identity
            )
        default:
            return nil
        }
    }

    // MARK: - Keyboard shortcut

    /// True for a key a shortcut can use (KeyName.parse): one character, or a special key name in
    /// any case ("return", "upArrow", "space", ...).
    static func isValidKeyName(_ key: String) -> Bool {
        KeyName.parse(key) != nil
    }

    /// The modifiers of a keyboard shortcut. Absent (or not an array of strings): command. An
    /// empty array: none (a bare key). Otherwise the known names, compared case-insensitively;
    /// when none is known: command.
    static func keyboardShortcutModifiers(_ value: Any?) -> Set<BaseModifiers.ModifierKey> {
        guard let names = value as? [String] else {
            return [.command]
        }
        if names.isEmpty {
            return []
        }
        let known = Set(names.compactMap { BaseModifiers.ModifierKey(rawValue: $0.lowercased()) })
        return known.isEmpty ? [.command] : known
    }

    /// A dictionary with a valid key (see isValidKeyName) and modifiers. nil otherwise.
    static func keyboardShortcut(_ value: Any?) -> BaseModifiers.KeyboardShortcut? {
        guard let dict = value as? [String: Any], let key = dict["key"] as? String, isValidKeyName(key) else {
            return nil
        }
        return BaseModifiers.KeyboardShortcut(key: key, modifiers: keyboardShortcutModifiers(dict["modifiers"]))
    }

    // MARK: - Navigation split view column width

    /// A positive number (a fixed width), or a dictionary with a positive ideal and optional
    /// positive min and max (others are dropped). nil otherwise.
    static func columnWidth(_ value: Any?) -> BaseModifiers.ColumnWidth? {
        if let dict = value as? [String: Any] {
            guard let ideal = dict.double(forKey: "ideal"), ideal > 0 else {
                return nil
            }
            let min = dict.double(forKey: "min").flatMap { $0 > 0 ? $0 : nil }
            let max = dict.double(forKey: "max").flatMap { $0 > 0 ? $0 : nil }
            return .range(min: min, ideal: ideal, max: max)
        }
        if let fixed = JSONNumber.double(value), fixed > 0 {
            return .fixed(fixed)
        }
        return nil
    }
}
