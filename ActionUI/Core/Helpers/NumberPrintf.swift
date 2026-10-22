// Core/Helpers/NumberPrintf.swift
/*
 A printf format with one number in it, as Stepper's labelFormat is ("Quantity: %.0f"). The same
 rule holds on every renderer (Android's NumberPrintf.kt and the web's NumberPrintf.js implement it
 too, and all of them check the cases in FormatParity/labelformat-cases.json):

 - Accepted: text with exactly one conversion among d i f F e E g G, with optional flags (- + space
   # 0), width and precision, plus any number of "%%". Anything else ("%@", "%s", "%d %d", "*"
   widths, length modifiers, the "'" grouping flag) is refused, where String(format:) would read
   arguments that are not there; so is a width or precision over 4096 (NumberPrintf.maxLength).
 - An integer conversion gets the value truncated toward zero; a value no 64-bit integer holds
   (infinite, NaN, beyond its range) is refused.
 - The number is formatted as C's printf formats it in the C locale, then its decimal point "." is
   the system's decimal separator. The text around it is kept as written.
 - A refused format shows the plain value: "%g", with the system's decimal separator.
 - NaN has no sign, whatever the flags (C libraries differ there).

 The system's decimal separator: on Apple, Locale.current's; on Linux, the C library's for the
 locale GTK sets from the user's at startup.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

enum NumberPrintf {
    /// A format split around its one conversion: the text before and after it ("%%" already "%"),
    /// the conversion as the C format to pass to vsnprintf (an integer one with the "l" length
    /// modifier), and whether it takes an integer.
    struct Parsed: Equatable {
        var prefix: String
        var conversion: String
        var suffix: String
        var isInteger: Bool
    }

    /// The largest width or precision accepted: larger ones would make texts no renderer can build
    /// alike (C prints up to INT_MAX characters, JavaScript strings end near 2^29, a JVM runs out of
    /// memory), and a typo such as "%1000000000d" would allocate gigabytes.
    static let maxLength = 4096

    /// The C locale for numbers, which vsnprintf formats in whatever locale the process is in.
    nonisolated(unsafe) private static let cLocale = newlocale(Int32(1) << LC_NUMERIC, "C", nil)

    /// `format` with `value` in it, or nil when the format is refused.
    static func format(_ format: String, _ value: Double, decimalSeparator: String = systemDecimalSeparator) -> String? {
        guard let parsed = parse(format) else { return nil }
        let number: String?
        if parsed.isInteger {
            guard value.isFinite, let integer = Int64(exactly: value.rounded(.towardZero)) else { return nil }
            number = printf(parsed.conversion, Int(integer))
        } else if value.isNaN {
            // No sign for NaN, where C libraries differ (glibc prints "+nan" for "%+f" and "-nan" for a
            // negative NaN, Darwin "nan" for both).
            number = printf(parsed.conversion.filter { $0 != "+" && $0 != " " }, Double.nan)
        } else {
            number = printf(parsed.conversion, value)
        }
        guard let number else { return nil }
        return parsed.prefix + localized(number, decimalSeparator) + parsed.suffix
    }

    /// The value as "%g" prints it, with the decimal separator: what a refused format shows instead.
    static func plain(_ value: Double, decimalSeparator: String = systemDecimalSeparator) -> String {
        localized(printf("%g", value) ?? "", decimalSeparator)
    }

    /// The decimal separator of the user's locale.
    static var systemDecimalSeparator: String {
        #if canImport(FoundationEssentials)
        // Linux: the C library's, for the locale GTK sets with setlocale(LC_ALL, "") at startup.
        guard let point = localeconv()?.pointee.decimal_point else { return "." }
        let separator = String(cString: point)
        return separator.isEmpty ? "." : separator
        #else
        return Locale.current.decimalSeparator ?? "."
        #endif
    }

    /// The format split around its one conversion; nil when the format is refused.
    static func parse(_ format: String) -> Parsed? {
        // Unicode scalars, not Characters: a Character can hold a "%" with a scalar before it (a
        // Prepend scalar such as U+0600 joins the next one), which the C library still reads as a
        // conversion.
        let scalars = Array(format.unicodeScalars)
        var prefix = String.UnicodeScalarView()
        var suffix = String.UnicodeScalarView()
        var conversion: String.UnicodeScalarView?
        var isInteger = false
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            index += 1
            guard scalar == "%" else {
                if conversion == nil { prefix.append(scalar) } else { suffix.append(scalar) }
                continue
            }
            guard index < scalars.count else { return nil }
            if scalars[index] == "%" {
                if conversion == nil { prefix.append("%") } else { suffix.append("%") }
                index += 1
                continue
            }
            guard conversion == nil else { return nil }
            var spec = String.UnicodeScalarView(["%"])
            while index < scalars.count, "-+ #0".unicodeScalars.contains(scalars[index]) {
                spec.append(scalars[index])
                index += 1
            }
            var width = ""
            while index < scalars.count, ("0"..."9").contains(scalars[index]) {
                width.unicodeScalars.append(scalars[index])
                index += 1
            }
            guard width.isEmpty || (Int(width).map { $0 <= maxLength } ?? false) else { return nil }
            spec.append(contentsOf: width.unicodeScalars)
            if index < scalars.count, scalars[index] == "." {
                spec.append(".")
                index += 1
                var precision = ""
                while index < scalars.count, ("0"..."9").contains(scalars[index]) {
                    precision.unicodeScalars.append(scalars[index])
                    index += 1
                }
                guard precision.isEmpty || (Int(precision).map { $0 <= maxLength } ?? false) else { return nil }
                spec.append(contentsOf: precision.unicodeScalars)
            }
            guard index < scalars.count, "difFeEgG".unicodeScalars.contains(scalars[index]) else { return nil }
            isInteger = scalars[index] == "d" || scalars[index] == "i"
            if isInteger {
                spec.append("l")
            }
            spec.append(scalars[index])
            index += 1
            conversion = spec
        }
        guard let conversion else { return nil }
        return Parsed(prefix: String(prefix), conversion: String(conversion), suffix: String(suffix), isInteger: isInteger)
    }

    /// The number with its decimal point as `separator` (a formatted number has at most one ".").
    private static func localized(_ number: String, _ separator: String) -> String {
        separator == "." ? number : number.replacing(".", with: separator, maxReplacements: 1)
    }

    /// vsnprintf in the C locale, twice: for the length, then the text (a va_list is used once).
    private static func printf(_ format: String, _ argument: CVarArg) -> String? {
        let previous = uselocale(cLocale)
        defer { uselocale(previous) }
        let length = withVaList([argument]) { vsnprintf(nil, 0, format, $0) }
        guard length >= 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(length) + 1)
        let written = buffer.withUnsafeMutableBufferPointer { bytes in
            withVaList([argument]) { vsnprintf(bytes.baseAddress, bytes.count, format, $0) }
        }
        guard written == length else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
