// Core/Helpers/NumberPrintf+Windows.swift
/*
 NumberPrintf's C formatting on Windows: the Microsoft C runtime has no uselocale, so the C locale
 is passed to its printf variants that take a locale as an argument. NumberPrintf.swift has the
 same on Apple and Linux.
*/

#if os(Windows)

import ucrt

extension NumberPrintf {
    /// The C locale for numbers, which the C runtime's printf would otherwise format in whatever
    /// locale the process is in.
    nonisolated(unsafe) private static let cLocale = _create_locale(LC_NUMERIC, "C")

    /// The C runtime's printf in the C locale, twice: for the length, then the text (a va_list is
    /// used once).
    static func printf(_ format: String, _ argument: CVarArg) -> String? {
        let length = withVaList([argument]) { _vscprintf_l(format, cLocale, $0) }
        guard length >= 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(length) + 1)
        let written = buffer.withUnsafeMutableBufferPointer { bytes in
            // The secure form: at most `length` characters and the terminating NUL, in a buffer of length + 1.
            withVaList([argument]) { _vsnprintf_s_l(bytes.baseAddress, bytes.count, Int(length), format, cLocale, $0) }
        }
        guard written == length else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

#endif
