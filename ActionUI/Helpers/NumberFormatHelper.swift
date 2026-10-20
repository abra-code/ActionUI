// Helpers/NumberFormatHelper.swift
/*
 NumberFormatHelper describes the number format of a formatted TextField (and a chart axis):
 integer, decimal, percent or currency, with optional fraction lengths, parsed from the
 "format", "fractionLength" and "currencyCode" properties.

 All model values remain String externally; conversion to/from numeric types is handled by the
 bindings in NumberFormatHelper+SwiftUI.swift. This file is Foundation-only, so every renderer
 shares the parsing.
*/

import Foundation

enum NumberFormatHelper: Equatable, Sendable {
    case integer
    case decimal(minFraction: Int?, maxFraction: Int?)
    case percent(minFraction: Int?, maxFraction: Int?)
    case currency(code: String, minFraction: Int?, maxFraction: Int?)

    /// Parses format-related properties from an element's properties dictionary.
    /// Returns nil if no "format" key is present.
    static func resolve(from properties: [String: Any]) -> NumberFormatHelper? {
        guard let format = properties["format"] as? String else { return nil }

        let (minFrac, maxFrac) = parseFractionLength(from: properties)

        switch format {
        case "integer":
            return .integer
        case "decimal":
            return .decimal(minFraction: minFrac, maxFraction: maxFrac)
        case "percent":
            return .percent(minFraction: minFrac, maxFraction: maxFrac)
        case "currency":
            let code = properties["currencyCode"] as? String ?? "USD"
            return .currency(code: code, minFraction: minFrac, maxFraction: maxFrac)
        default:
            return nil
        }
    }

    /// Extracts the initial numeric value from properties as a String.
    /// Accepts "value" (Int, Double, or String) or falls back to "text".
    static func initialValueString(from properties: [String: Any]) -> String {
        let value = properties["value"]
        // Only an Int, Double or String "value" counts: a Float,
        // Int64 or CGFloat set at runtime falls through to "text".
        if value is Int || value is Double || value is String {
            if let intVal = value as? Int { return String(intVal) }
            if let doubleVal = properties.double(forKey: "value") { return String(doubleVal) }
            if let strVal = value as? String { return strVal }
        }
        if let text = properties["text"] as? String { return text }
        return "0"
    }

    // MARK: - Private

    private static func parseFractionLength(from properties: [String: Any]) -> (Int?, Int?) {
        guard let fractionLength = properties["fractionLength"] else { return (nil, nil) }

        if let exact = fractionLength as? Int {
            return (exact, exact)
        }
        if let dict = fractionLength as? [String: Any] {
            let min = dict["min"] as? Int
            let max = dict["max"] as? Int
            return (min, max)
        }
        return (nil, nil)
    }
}
