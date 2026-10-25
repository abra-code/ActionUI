// Sources/Formatting/SystemLocale.swift
/*
 The locale the user's system settings ask dates and numbers to follow: the C library's locale for
 the category, LC_TIME for dates, LC_NUMERIC for numbers and LC_MONETARY for amounts of money,
 which GTK sets from the environment at startup. GNOME's Settings sets these from Region, Formats,
 apart from the language (LC_MESSAGES), as macOS formats by its Region whatever the language; ICU's
 own default follows the language, so the formatters name the category's locale instead.

 The C library's names ("de_DE.UTF-8", "sr_RS.UTF-8@latin") become ICU's ("de_DE", "sr_RS"): the
 character set and the modifier go. The C and POSIX locales name nothing, leaving ICU's default.
*/

import Glibc

@MainActor
enum SystemLocale {
    /// The ICU locale for `category` (LC_TIME, LC_NUMERIC, LC_MONETARY); nil for the C locale,
    /// when ICU's default applies.
    static func icuLocale(for category: Int32) -> String? {
        guard let name = setlocale(category, nil) else { return nil }
        return icuLocale(fromPOSIX: String(cString: name))
    }

    /// ICU's name for a C library locale name: "de_DE.UTF-8" is "de_DE"; nil for C and POSIX.
    static func icuLocale(fromPOSIX name: String) -> String? {
        let language = name.prefix { $0 != "." && $0 != "@" }
        guard !language.isEmpty, language != "C", language != "POSIX" else { return nil }
        return String(language)
    }
}
