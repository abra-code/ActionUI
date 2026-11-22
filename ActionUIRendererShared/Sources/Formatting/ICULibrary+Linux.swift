// Sources/Formatting/ICULibrary+Linux.swift
/*
 Finding ICU on Linux. Every desktop Linux install has some ICU (Debian 13: libicu76), whose C
 functions carry the major version in their names (udat_format_76), and versions differ between
 distributions, so ActionUI names none: for N from 120 down to 50 it opens libicui18n.so.N (which
 brings in libicuuc.so.N, its dependency), the first N that opens wins, and each function is looked
 up as name_N, then as the plain name (ICU built without renaming). The unversioned libicui18n.so
 is a developer package's link, not on users' systems. A miss costs about 4 microseconds (13 the
 first time; measured on Debian 13), once per process, when the first date is formatted. .NET finds
 ICU the same way on Linux (System.Globalization.Native's pal_icushim.c).
*/

#if os(Linux)

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

extension ICULibrary {
    /// The newest ICU that opens, when it carries every function used; nil otherwise. The library
    /// stays loaded for the life of the process.
    static func load() -> ICULibrary? {
        for version in stride(from: 120, through: 50, by: -1) {
            guard let i18n = dlopen("libicui18n.so.\(version)", RTLD_NOW | RTLD_LOCAL) else { continue }
            if let library = ICULibrary(version: version, symbol: { dlsym(i18n, "\($0)_\(version)") ?? dlsym(i18n, $0) }) {
                ActionUIModel.shared.logger.log("ICU \(version) formats dates and numbers by locale", .verbose)
                return library
            }
            dlclose(i18n)
            ActionUIModel.shared.logger.log("ICU \(version) lacks a function ActionUI uses; dates follow the C library's locale and numbers show plain digits", .info)
            return nil
        }
        ActionUIModel.shared.logger.log("No ICU found; dates follow the C library's locale and numbers show plain digits", .info)
        return nil
    }
}

#endif
