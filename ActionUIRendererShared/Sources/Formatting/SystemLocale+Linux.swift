// Sources/Formatting/SystemLocale+Linux.swift
/*
 The system's locale on Linux: the C library's locale for the category, LC_TIME for dates,
 LC_NUMERIC for numbers and LC_MONETARY for amounts of money, which GTK sets from the environment at
 startup. GNOME's Settings sets these from Region, Formats, apart from the language (LC_MESSAGES).
*/

#if os(Linux)

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

extension SystemLocale {
    /// The ICU locale for `category`; nil for the C locale, when ICU's default applies.
    static func icuLocale(for category: Category) -> String? {
        let cCategory: Int32
        switch category {
        case .time: cCategory = LC_TIME
        case .numbers: cCategory = LC_NUMERIC
        case .money: cCategory = LC_MONETARY
        }
        guard let name = setlocale(cCategory, nil) else { return nil }
        return icuLocale(fromPOSIX: String(cString: name))
    }
}

#endif
