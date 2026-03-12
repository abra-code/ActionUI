// Helpers/NumberFormatHelper.swift
/*
 NumberFormatHelper provides utilities for building SwiftUI formatted TextFields
 that bridge between ActionUI's String-based model values and SwiftUI's typed
 value:format: TextField constructors.

 All model values remain String externally; conversion to/from numeric types
 is handled internally by the bindings this helper creates.
*/

import SwiftUI

enum NumberFormatHelper {
    case integer
    case decimal(minFraction: Int?, maxFraction: Int?)
    case percent(minFraction: Int?, maxFraction: Int?)
    case currency(code: String, minFraction: Int?, maxFraction: Int?)

    /// Parses format-related properties from a validated properties dictionary.
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
        if let intVal = properties["value"] as? Int { return String(intVal) }
        if let doubleVal = properties.double(forKey: "value") { return String(doubleVal) }
        if let strVal = properties["value"] as? String { return strVal }
        if let text = properties["text"] as? String { return text }
        return "0"
    }

    // MARK: - Binding helpers

    /// Creates a Binding<Int> that bridges to a String-based model value.
    @MainActor static func intBinding(
        model: ViewModel,
        defaultValue: String,
        onValueChange: @escaping (String) -> Void
    ) -> Binding<Int> {
        Binding<Int>(
            get: {
                MainActor.assumeIsolated {
                    Int(model.value as? String ?? defaultValue) ?? 0
                }
            },
            set: { newValue in
                MainActor.assumeIsolated {
                    let str = String(newValue)
                    guard str != model.value as? String else { return }
                    onValueChange(str)
                }
            }
        )
    }

    /// Creates a Binding<Double> that bridges to a String-based model value.
    @MainActor static func doubleBinding(
        model: ViewModel,
        defaultValue: String,
        onValueChange: @escaping (String) -> Void
    ) -> Binding<Double> {
        Binding<Double>(
            get: {
                MainActor.assumeIsolated {
                    Double(model.value as? String ?? defaultValue) ?? 0.0
                }
            },
            set: { newValue in
                MainActor.assumeIsolated {
                    let str = String(newValue)
                    guard str != model.value as? String else { return }
                    onValueChange(str)
                }
            }
        )
    }

    // MARK: - View construction

    /// Builds a formatted SwiftUI.TextField for the given number format.
    /// The returned view does NOT include .onSubmit — the caller should apply it.
    @MainActor static func buildFormattedTextField(
        title: String,
        prompt: SwiftUI.Text?,
        format: NumberFormatHelper,
        model: ViewModel,
        defaultValue: String,
        onValueChange: @escaping (String) -> Void
    ) -> any SwiftUI.View {
        switch format {
        case .integer:
            let binding = intBinding(model: model, defaultValue: defaultValue, onValueChange: onValueChange)
            return SwiftUI.TextField(title, value: binding, format: .number, prompt: prompt)

        case .decimal(let minFrac, let maxFrac):
            let binding = doubleBinding(model: model, defaultValue: defaultValue, onValueChange: onValueChange)
            if let style = decimalStyle(minFraction: minFrac, maxFraction: maxFrac) {
                return SwiftUI.TextField(title, value: binding, format: style, prompt: prompt)
            }
            return SwiftUI.TextField(title, value: binding, format: .number, prompt: prompt)

        case .percent(let minFrac, let maxFrac):
            let binding = doubleBinding(model: model, defaultValue: defaultValue, onValueChange: onValueChange)
            if let style = percentStyle(minFraction: minFrac, maxFraction: maxFrac) {
                return SwiftUI.TextField(title, value: binding, format: style, prompt: prompt)
            }
            return SwiftUI.TextField(title, value: binding, format: .percent, prompt: prompt)

        case .currency(let code, let minFrac, let maxFrac):
            let binding = doubleBinding(model: model, defaultValue: defaultValue, onValueChange: onValueChange)
            if let style = currencyStyle(code: code, minFraction: minFrac, maxFraction: maxFrac) {
                return SwiftUI.TextField(title, value: binding, format: style, prompt: prompt)
            }
            return SwiftUI.TextField(title, value: binding, format: .currency(code: code), prompt: prompt)
        }
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

    private static func decimalStyle(
        minFraction: Int?, maxFraction: Int?
    ) -> FloatingPointFormatStyle<Double>? {
        guard minFraction != nil || maxFraction != nil else { return nil }
        let min = minFraction ?? 0
        let max = maxFraction ?? min
        return .number.precision(.fractionLength(min...max))
    }

    private static func percentStyle(
        minFraction: Int?, maxFraction: Int?
    ) -> FloatingPointFormatStyle<Double>.Percent? {
        guard minFraction != nil || maxFraction != nil else { return nil }
        let min = minFraction ?? 0
        let max = maxFraction ?? min
        return .percent.precision(.fractionLength(min...max))
    }

    private static func currencyStyle(
        code: String, minFraction: Int?, maxFraction: Int?
    ) -> FloatingPointFormatStyle<Double>.Currency? {
        guard minFraction != nil || maxFraction != nil else { return nil }
        let min = minFraction ?? 0
        let max = maxFraction ?? min
        return .currency(code: code).precision(.fractionLength(min...max))
    }
}
