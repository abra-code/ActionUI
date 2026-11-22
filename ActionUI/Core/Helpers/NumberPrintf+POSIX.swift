// Core/Helpers/NumberPrintf+POSIX.swift
/*
 NumberPrintf's C formatting on Apple platforms and Linux: vsnprintf, with the C locale made the
 thread's own for the call (uselocale). Windows, whose C runtime has no uselocale, has its own
 (NumberPrintf+Windows.swift).
*/

#if !os(Windows)

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

extension NumberPrintf {
    /// The C locale for numbers, which vsnprintf formats in whatever locale the process is in.
    nonisolated(unsafe) private static let cLocale = newlocale(Int32(1) << LC_NUMERIC, "C", nil)

    /// vsnprintf in the C locale, twice: for the length, then the text (a va_list is used once).
    static func printf(_ format: String, _ argument: CVarArg) -> String? {
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

#endif
