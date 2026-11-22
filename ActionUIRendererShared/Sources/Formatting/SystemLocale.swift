// Sources/Formatting/SystemLocale.swift
/*
 The locale the user's system settings ask dates, numbers and amounts of money to follow, as an
 ICU locale name ("de_DE"), for the formatters to name: ICU's own default follows the language,
 where macOS formats by its Region whatever the language. Each platform reads its settings in a
 file of its own (Linux: SystemLocale+Linux.swift).

 The C library's names ("de_DE.UTF-8", "sr_RS.UTF-8@latin") become ICU's ("de_DE", "sr_RS"): the
 character set and the modifier go. The C and POSIX locales name nothing, leaving ICU's default.
*/

@MainActor
enum SystemLocale {
    /// What a locale is asked for.
    enum Category {
        case time
        case numbers
        case money
    }

    /// ICU's name for a C library locale name: "de_DE.UTF-8" is "de_DE"; nil for C and POSIX.
    static func icuLocale(fromPOSIX name: String) -> String? {
        let language = name.prefix { $0 != "." && $0 != "@" }
        guard !language.isEmpty, language != "C", language != "POSIX" else { return nil }
        return String(language)
    }
}
