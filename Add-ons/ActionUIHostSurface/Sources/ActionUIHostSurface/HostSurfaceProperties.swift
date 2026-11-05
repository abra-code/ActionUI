// Add-ons/ActionUIHostSurface/Sources/ActionUIHostSurface/HostSurfaceProperties.swift
//
// The element's own properties, read from the dictionary ActionUI passes to buildView. Pure, so the
// rules are unit-tested without a view. Ill-typed values warn and fall back to the default, like
// every ActionUI element.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import ActionUI

/// What the element asked for in "kind".
enum HostSurfaceKindRequest: Equatable {
    /// "native", or absent: the platform's own surface (a Metal layer on Apple platforms).
    case native
    /// A kind this platform lacks ("sink", "gl"), or an unknown one: the element draws a placeholder
    /// and announces no surface.
    case unsupported(String)
}

struct HostSurfaceProperties: Equatable {
    var surfaceName: String
    var kind: HostSurfaceKindRequest
    var continuous: Bool
    /// Frames per second; 0 is the display rate.
    var preferredFrameRate: Double
    var focusable: Bool
    var opaque: Bool
    var hidden: Bool
    var idealWidth: Double
    var idealHeight: Double

    static let defaultIdealWidth = 320.0
    static let defaultIdealHeight = 240.0

    init(surfaceName: String = "", kind: HostSurfaceKindRequest = .native, continuous: Bool = false,
         preferredFrameRate: Double = 0, focusable: Bool = true, opaque: Bool = true, hidden: Bool = false,
         idealWidth: Double = HostSurfaceProperties.defaultIdealWidth,
         idealHeight: Double = HostSurfaceProperties.defaultIdealHeight) {
        self.surfaceName = surfaceName
        self.kind = kind
        self.continuous = continuous
        self.preferredFrameRate = preferredFrameRate
        self.focusable = focusable
        self.opaque = opaque
        self.hidden = hidden
        self.idealWidth = idealWidth
        self.idealHeight = idealHeight
    }

    init(_ properties: [String: Any], logger: any ActionUILogger) {
        self.init()
        if let raw = properties["surfaceName"] {
            if let name = raw as? String, !name.isEmpty {
                surfaceName = name
            } else {
                logger.log("HostSurface: 'surfaceName' must be a non-empty String, got \(raw); no client can bind to it", .warning)
            }
        } else {
            logger.log("HostSurface: 'surfaceName' is required; no client can bind to this surface", .warning)
        }
        if let raw = properties["kind"] {
            switch raw as? String {
            case "native":
                kind = .native
            case let name?:
                logger.log("HostSurface: kind '\(name)' is not available on this platform; drawing a placeholder", .warning)
                kind = .unsupported(name)
            case nil:
                logger.log("HostSurface: 'kind' must be a String, got \(raw); drawing a placeholder", .warning)
                kind = .unsupported("\(raw)")
            }
        }
        continuous = Self.bool(properties, "continuous", default: false, logger: logger)
        focusable = Self.bool(properties, "focusable", default: true, logger: logger)
        opaque = Self.bool(properties, "opaque", default: true, logger: logger)
        hidden = Self.bool(properties, "hidden", default: false, logger: logger)
        preferredFrameRate = Self.number(properties, "preferredFrameRate", default: 0, logger: logger)
        idealWidth = Self.number(properties, "idealWidth", default: Self.defaultIdealWidth, logger: logger)
        idealHeight = Self.number(properties, "idealHeight", default: Self.defaultIdealHeight, logger: logger)
    }

    /// A JSON Boolean. NSNumber-backed booleans from JSONSerialization arrive as Bool.
    private static func bool(_ properties: [String: Any], _ key: String, default value: Bool,
                             logger: any ActionUILogger) -> Bool {
        guard let raw = properties[key] else {
            return value
        }
        guard let flag = raw as? Bool else {
            logger.log("HostSurface: '\(key)' must be a Boolean, got \(raw); using \(value)", .warning)
            return value
        }
        return flag
    }

    /// A JSON number, zero or greater.
    private static func number(_ properties: [String: Any], _ key: String, default value: Double,
                               logger: any ActionUILogger) -> Double {
        guard let raw = properties[key] else {
            return value
        }
        let number: Double?
        switch raw {
        case is Bool:
            number = nil
        case let int as Int:
            number = Double(int)
        case let double as Double:
            number = double
        case let float as Float:
            number = Double(float)
        default:
            number = nil
        }
        guard let number, number.isFinite, number >= 0 else {
            logger.log("HostSurface: '\(key)' must be a number of zero or more, got \(raw); using \(value)", .warning)
            return value
        }
        return number
    }
}
