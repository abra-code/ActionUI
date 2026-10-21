// Core/Helpers/PlainText.swift
/*
 The little text work Core needs, in plain Swift: FoundationEssentials, which Core builds against
 on Linux, has neither `trimmingCharacters(in:)` nor `String(format:)`.
*/

enum PlainText {
    /// `text` without white space at its start and its end, the same characters Foundation's
    /// `.whitespacesAndNewlines` drops (isWhite). Compared as Unicode scalars, so a carriage return
    /// is removed even where it forms one Character with a following line feed.
    static func trimmed<Text: StringProtocol>(_ text: Text) -> String {
        var scalars = text.unicodeScalars[...]
        while let first = scalars.first, isWhite(first) {
            scalars = scalars.dropFirst()
        }
        while let last = scalars.last, isWhite(last) {
            scalars = scalars.dropLast()
        }
        return String(String.UnicodeScalarView(scalars))
    }

    // The Unicode White_Space characters, plus U+200B ZERO WIDTH SPACE, which has no White_Space
    // property but which Foundation's set includes.
    private static func isWhite(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace || scalar == "\u{200B}"
    }

    /// `value` in decimal, with leading zeros up to `width` characters, as `String(format: "%0*d")`
    /// writes it: a minus sign counts toward the width, and a longer number is not cut.
    static func zeroPadded(_ value: Int, width: Int) -> String {
        let sign = value < 0 ? "-" : ""
        let digits = String(value.magnitude)
        let padding = max(0, width - sign.count - digits.count)
        return sign + String(repeating: "0", count: padding) + digits
    }
}
