// Sources/Formatting/SystemLocale+Windows.swift
/*
 The system's locale on Windows: the user's locale for formats (Settings, Time & language, Language &
 region, Regional format), which Windows keeps apart from the display language, as macOS formats by its
 Region. Windows has one such locale for dates, numbers and money alike. Its BCP 47 name ("en-US",
 "sr-Latn-RS") becomes ICU's form ("en_US", "sr_Latn_RS").
*/

#if os(Windows)

import WinSDK

extension SystemLocale {
    /// The ICU locale for `category`: the user's locale for formats, the same for every category; nil
    /// when Windows does not say.
    static func icuLocale(for category: Category) -> String? {
        var buffer = [WCHAR](repeating: 0, count: Int(LOCALE_NAME_MAX_LENGTH))
        let count = buffer.withUnsafeMutableBufferPointer { GetUserDefaultLocaleName($0.baseAddress, Int32($0.count)) }
        // The count includes the terminating zero.
        guard count > 1 else { return nil }
        let name = String(decoding: buffer[..<Int(count - 1)], as: UTF16.self)
        return icuLocale(fromBCP47: name)
    }

    /// ICU's name for a BCP 47 locale name: "en-US" is "en_US"; nil for an empty name.
    static func icuLocale(fromBCP47 name: String) -> String? {
        name.isEmpty ? nil : name.replacing("-", with: "_")
    }
}

#endif
