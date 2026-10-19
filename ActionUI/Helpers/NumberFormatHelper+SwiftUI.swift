// Helpers/NumberFormatHelper+SwiftUI.swift
/*
 The SwiftUI side of NumberFormatHelper: the bindings that bridge the String model value to the
 Int or Double a formatted SwiftUI.TextField edits, the field itself, and the FormatStyle for
 each format. The format description and its parsing are in NumberFormatHelper.swift.
*/

import SwiftUI

extension NumberFormatHelper {
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
    /// The returned view does NOT include .onSubmit - the caller should apply it.
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
