// Sources/Formatting/NumberFormatting.swift
/*
 Numbers as the user's locale writes and reads them, for a TextField with a number format: ICU's
 number formats (unum), from the same Unicode locale data (CLDR) SwiftUI's FormatStyle uses on
 Apple ("$1,234.50" in en_US, "1.234,50 $" in de_DE for USD).

 - Fraction digits as SwiftUI's styles show them (measured on macOS 27): decimal and percent at
   most 6 (ICU's own default is 3 and 0), currency the currency's own (USD 2, JPY 0), integer none;
   a fractionLength replaces them. ICU rounds half to even, as FormatStyle does.
 - Reading takes the number at the start of the text, without the spaces around it, as SwiftUI's
   lenient parse does (measured: "12abc" is 12, "7%" in a decimal field 7, "12" in a percent field
   0.12 and in a currency field 12, "1.234,5" in en_US 1.234 since a grouping separator needs three
   digits after it, another currency's symbol nothing); ICU's lenient parse gives each of these
   (checked with ICU 76 against the macOS table, en_US and de_DE).

 Without ICU (ICULibrary), plain digits with a period: the value rounded to the fraction digits, a
 percent with "%" after it, a currency with its code before it; reading takes the number at the
 start (after a currency code; a percent's is the fraction).

 An ICU formatter is kept per locale and format: a window has a few.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Glibc

@MainActor
enum NumberFormatting {
    /// `value` as `locale` writes it in `format`; nil for the locale the system's settings give
    /// numbers (SystemLocale: LC_NUMERIC, LC_MONETARY for a currency), or localeForTesting.
    static func string(_ value: Double, format: NumberFormatSpec, locale: String? = nil) -> String {
        let key = Key(format: format, locale: locale ?? localeForTesting ?? systemLocale(format))
        if let icu = ICULibrary.shared, let formatter = formatter(icu, key), let text = icuString(icu, formatter, value) {
            return text
        }
        return fallbackString(value, format: format)
    }

    /// The number at the start of `text` (spaces around it ignored) as `locale` writes numbers in
    /// `format`, a percent as its fraction ("12%" is 0.12); nil when the text does not start with
    /// one.
    static func number(from text: String, format: NumberFormatSpec, locale: String? = nil) -> Double? {
        let trimmed = String(text.drop { $0.isWhitespace }.reversed().drop { $0.isWhitespace }.reversed())
        guard !trimmed.isEmpty else { return nil }
        let key = Key(format: format, locale: locale ?? localeForTesting ?? systemLocale(format))
        if let icu = ICULibrary.shared, let formatter = formatter(icu, key) {
            let utf16 = Array(trimmed.utf16)
            var position: Int32 = 0
            var status = ICULibrary.noError
            let value = icu.parseNumber(formatter, utf16, Int32(utf16.count), &position, &status)
            return status > ICULibrary.noError ? nil : value
        }
        return fallbackNumber(trimmed, format: format)
    }

    /// The locale tests format in when they pass none, instead of the box's.
    static var localeForTesting: String?

    /// The system's locale for numbers in `format`: LC_MONETARY for amounts of money, else
    /// LC_NUMERIC.
    private static func systemLocale(_ format: NumberFormatSpec) -> String? {
        if case .currency = format { return SystemLocale.icuLocale(for: LC_MONETARY) }
        return SystemLocale.icuLocale(for: LC_NUMERIC)
    }

    private struct Key: Hashable {
        var format: NumberFormatSpec
        var locale: String?
    }

    /// ICU's UNumberFormat for each key, kept for the life of the process.
    private static var formatters: [Key: OpaquePointer] = [:]
    /// Keys whose formatter ICU could not make: they use the fallback without asking ICU again.
    private static var failedKeys: Set<Key> = []
    private static var reportedFailure = false

    private static func formatter(_ icu: ICULibrary, _ key: Key) -> OpaquePointer? {
        if let formatter = formatters[key] { return formatter }
        guard !failedKeys.contains(key) else { return nil }
        guard let formatter = makeFormatter(icu, key) else {
            failedKeys.insert(key)
            return nil
        }
        formatters[key] = formatter
        return formatter
    }

    private static func makeFormatter(_ icu: ICULibrary, _ key: Key) -> OpaquePointer? {
        let style: Int32
        switch key.format {
        case .integer, .decimal: style = ICULibrary.decimalStyle
        case .percent: style = ICULibrary.percentStyle
        case .currency: style = ICULibrary.currencyStyle
        }
        var status = ICULibrary.noError
        let opened = withOptionalCString(key.locale) { icu.openNumberFormat(style, nil, 0, $0, nil, &status) }
        guard let formatter = opened, status <= ICULibrary.noError else {
            report("unum_open", status)
            return nil
        }
        if case .currency(let code, _, _) = key.format {
            // Before the fraction digits: naming the currency sets its own.
            let utf16 = Array(code.utf16)
            icu.setNumberTextAttribute(formatter, ICULibrary.currencyCode, utf16, Int32(utf16.count), &status)
            guard status <= ICULibrary.noError else {
                report("unum_setTextAttribute", status)
                return nil
            }
        }
        if let digits = fractionDigits(key.format) {
            // The maximum first: it lowers a larger minimum, which a later minimum then sets.
            icu.setNumberAttribute(formatter, ICULibrary.maxFractionDigits, Int32(clamping: digits.upperBound))
            icu.setNumberAttribute(formatter, ICULibrary.minFractionDigits, Int32(clamping: digits.lowerBound))
        }
        icu.setNumberAttribute(formatter, ICULibrary.lenientParse, 1)
        return formatter
    }

    /// The fraction digits SwiftUI's style for `format` shows; nil for a currency's own.
    static func fractionDigits(_ format: NumberFormatSpec) -> ClosedRange<Int>? {
        switch format {
        case .integer:
            return 0...0
        case .decimal(let minimum, let maximum), .percent(let minimum, let maximum):
            return NumberFormatSpec.fractionRange(minFraction: minimum, maxFraction: maximum) ?? 0...6
        case .currency(_, let minimum, let maximum):
            return NumberFormatSpec.fractionRange(minFraction: minimum, maxFraction: maximum)
        }
    }

    private static func icuString(_ icu: ICULibrary, _ formatter: OpaquePointer, _ value: Double) -> String? {
        var capacity: Int32 = 64
        while true {
            var status = ICULibrary.noError
            var buffer = [UInt16](repeating: 0, count: Int(capacity))
            let length = icu.formatNumber(formatter, value, &buffer, capacity, nil, &status)
            if length > capacity, capacity < 4096 {
                capacity = length + 1
                continue
            }
            guard status <= ICULibrary.noError, length >= 0, length <= capacity else {
                report("unum_formatDouble", status)
                return nil
            }
            return String(decoding: buffer.prefix(Int(length)), as: UTF16.self)
        }
    }

    /// Logs an ICU failure once (the call falls back to plain digits).
    private static func report(_ function: String, _ status: ICULibrary.ErrorCode) {
        guard !reportedFailure else { return }
        reportedFailure = true
        ActionUIModel.shared.logger.log("ICU \(function) failed (status \(status)); numbers show plain digits", .warning)
    }

    // MARK: - Without ICU

    private static func fallbackString(_ value: Double, format: NumberFormatSpec) -> String {
        let digits = fractionDigits(format) ?? 2...2
        var number: String
        switch format {
        case .percent: number = fixed(value * 100, digits: digits.upperBound)
        default: number = fixed(value, digits: digits.upperBound)
        }
        // Trailing zeros past the minimum go, and the period with them when nothing follows it.
        if let period = number.firstIndex(of: ".") {
            var fraction = number[number.index(after: period)...]
            while fraction.count > digits.lowerBound, fraction.last == "0" { fraction.removeLast() }
            number = String(number[..<period]) + (fraction.isEmpty ? "" : "." + fraction)
        }
        switch format {
        case .percent: return number + "%"
        case .currency(let code, _, _): return code + " " + number
        default: return number
        }
    }

    /// `value` with `digits` digits after a period, rounded (the C library's %.*f, in the C locale's
    /// form whatever LC_NUMERIC says).
    private static func fixed(_ value: Double, digits: Int) -> String {
        guard value.isFinite else { return String(value) }
        var buffer = [CChar](repeating: 0, count: 400)
        let length = withVaList([Int32(clamping: digits), value]) { vsnprintf(&buffer, buffer.count, "%.*f", $0) }
        guard length > 0 else { return String(value) }
        let text = String(decoding: buffer.prefix(min(Int(length), buffer.count - 1)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        // A locale with a decimal comma writes one; plain digits use a period.
        return String(text.map { $0 == "," ? "." : $0 })
    }

    private static func fallbackNumber(_ text: String, format: NumberFormatSpec) -> Double? {
        var rest = Substring(text)
        if case .currency(let code, _, _) = format, rest.hasPrefix(code) {
            rest = rest.dropFirst(code.count).drop { $0 == " " }
        }
        guard let value = Double(leadingNumber(rest)) else { return nil }
        if case .percent = format { return value / 100 }
        return value
    }

    /// The plain number `text` starts with: a sign, digits with a period among them, an exponent
    /// ("-12.5e3"); empty when it starts with none.
    private static func leadingNumber(_ text: Substring) -> Substring {
        var end = text.startIndex
        func take(_ accept: (Character) -> Bool) -> Bool {
            guard end < text.endIndex, accept(text[end]) else { return false }
            end = text.index(after: end)
            return true
        }
        _ = take { $0 == "-" || $0 == "+" }
        var digits = 0
        while take({ $0.isASCII && $0.isNumber }) { digits += 1 }
        if take({ $0 == "." }) {
            while take({ $0.isASCII && $0.isNumber }) { digits += 1 }
        }
        guard digits > 0 else { return "" }
        let mantissaEnd = end
        if take({ $0 == "e" || $0 == "E" }) {
            _ = take { $0 == "-" || $0 == "+" }
            var exponentDigits = 0
            while take({ $0.isASCII && $0.isNumber }) { exponentDigits += 1 }
            if exponentDigits == 0 { end = mantissaEnd }
        }
        return text[..<end]
    }

    private static func withOptionalCString<Result>(_ string: String?, _ body: (UnsafePointer<CChar>?) -> Result) -> Result {
        guard let string else { return body(nil) }
        return string.withCString(body)
    }
}
