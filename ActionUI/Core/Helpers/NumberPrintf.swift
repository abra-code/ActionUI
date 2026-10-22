// Core/Helpers/NumberPrintf.swift
/*
 A printf format with one number in it, as Stepper's labelFormat is ("Quantity: %.0f"), on Apple
 and Linux. Only formats that are safe with one Double are accepted: exactly one conversion among
 d i f F e E g G, with optional flags, width and precision, plus any number of "%%". Anything else
 ("%@", "%s", "%d %d", "*" widths, length modifiers) is refused, where String(format:) would read
 arguments that are not there.

 The number is formatted by the C library (vsnprintf), so it follows LC_NUMERIC: on Linux GTK sets
 it from the user's locale at startup; an Apple app keeps the C locale, whose decimal point is ".",
 as String(format:) without a locale prints. An integer conversion gets the value as an Int
 (through "%ld"); a value no Int holds (infinite, NaN, beyond Int's range) is refused.
*/

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

enum NumberPrintf {
    /// `format` with `value` in it, or nil when the format is refused.
    static func format(_ format: String, _ value: Double) -> String? {
        guard let parsed = parse(format) else { return nil }
        if parsed.isInteger {
            guard value.isFinite, let integer = Int(exactly: value.rounded(.towardZero)) else { return nil }
            return printf(parsed.cFormat, integer)
        }
        return printf(parsed.cFormat, value)
    }

    /// The value as "%g" prints it: what a refused format shows instead.
    static func plain(_ value: Double) -> String {
        printf("%g", value) ?? ""
    }

    /// The C format to pass to vsnprintf (an integer conversion gets the "l" length modifier), and
    /// whether the one conversion takes an integer; nil when the format is refused.
    static func parse(_ format: String) -> (cFormat: String, isInteger: Bool)? {
        // Unicode scalars, not Characters: a Character can hold a "%" with a scalar before it (a
        // Prepend scalar such as U+0600 joins the next one), which the C library still reads as a
        // conversion.
        let scalars = Array(format.unicodeScalars)
        var output = String.UnicodeScalarView()
        var conversion: Unicode.Scalar?
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            output.append(scalar)
            index += 1
            guard scalar == "%" else { continue }
            guard index < scalars.count else { return nil }
            if scalars[index] == "%" {
                output.append("%")
                index += 1
                continue
            }
            guard conversion == nil else { return nil }
            while index < scalars.count, "-+ #0'".unicodeScalars.contains(scalars[index]) {
                output.append(scalars[index])
                index += 1
            }
            while index < scalars.count, ("0"..."9").contains(scalars[index]) {
                output.append(scalars[index])
                index += 1
            }
            if index < scalars.count, scalars[index] == "." {
                output.append(".")
                index += 1
                while index < scalars.count, ("0"..."9").contains(scalars[index]) {
                    output.append(scalars[index])
                    index += 1
                }
            }
            guard index < scalars.count, "difFeEgG".unicodeScalars.contains(scalars[index]) else { return nil }
            conversion = scalars[index]
            if conversion == "d" || conversion == "i" {
                output.append("l")
            }
            output.append(scalars[index])
            index += 1
        }
        guard let conversion else { return nil }
        return (String(output), conversion == "d" || conversion == "i")
    }

    /// vsnprintf, twice: for the length, then the text (a va_list is used once).
    private static func printf(_ format: String, _ argument: CVarArg) -> String? {
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
