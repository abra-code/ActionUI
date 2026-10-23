// Sources/Formatting/ICULibrary.swift
/*
 The system's ICU, found and loaded at run time, for formatting dates (and later numbers) by the
 user's locale: FoundationEssentials cannot do that, and full Foundation would bring 45 MB of ICU
 data into libActionUI.so. Every desktop Linux install has some ICU (Debian 13: libicu76), whose C
 functions carry the major version in their names (udat_format_76), and versions differ between
 distributions, so ActionUI names none: for N from 120 down to 50 it opens libicui18n.so.N (which
 brings in libicuuc.so.N, its dependency), the first N that opens wins, and each function is looked
 up as name_N, then as the plain name (ICU built without renaming). The unversioned libicui18n.so
 is a developer package's link, not on users' systems. A miss costs about 4 microseconds (13 the
 first time; measured on Debian 13), once per process, when the first date is formatted. A missing
 function disables ICU as a whole, as does no library at all; callers then fall back to GLib
 (DateFormatting). .NET finds ICU the same way on Linux (System.Globalization.Native's
 pal_icushim.c).

 No ICU header is used: the few C types are declared here (UChar is UInt16, UErrorCode Int32, UDate
 Double milliseconds, the opened objects opaque pointers), with the values the formatters need
 taken from the ICU 76 headers; these values do not change between ICU versions.
*/

import Glibc

@MainActor
final class ICULibrary {
    typealias ErrorCode = Int32
    typealias OpenPatternGenerator = @convention(c) (UnsafePointer<CChar>?, UnsafeMutablePointer<ErrorCode>?) -> OpaquePointer?
    typealias ClosePatternGenerator = @convention(c) (OpaquePointer?) -> Void
    typealias BestPattern = @convention(c) (OpaquePointer?, UnsafePointer<UInt16>?, Int32, UnsafeMutablePointer<UInt16>?, Int32,
                                            UnsafeMutablePointer<ErrorCode>?) -> Int32
    typealias OpenDateFormat = @convention(c) (Int32, Int32, UnsafePointer<CChar>?, UnsafePointer<UInt16>?, Int32,
                                               UnsafePointer<UInt16>?, Int32, UnsafeMutablePointer<ErrorCode>?) -> OpaquePointer?
    typealias FormatDate = @convention(c) (OpaquePointer?, Double, UnsafeMutablePointer<UInt16>?, Int32, OpaquePointer?,
                                           UnsafeMutablePointer<ErrorCode>?) -> Int32

    /// U_ZERO_ERROR; an ICU call failed when its status is above it (warnings are below).
    static let noError: ErrorCode = 0
    /// UDAT_PATTERN, the style that tells udat_open to use the pattern it is given.
    static let patternStyle: Int32 = -2

    /// The loaded ICU, or nil when none was found (or a test disabled it).
    static var shared: ICULibrary? {
        if disabledForTesting { return nil }
        if !searched {
            searched = true
            loaded = load()
        }
        return loaded
    }

    /// Tests run the formatters through their fallback with this set.
    static var disabledForTesting = false

    private static var searched = false
    private static var loaded: ICULibrary?

    let version: Int
    /// udatpg_open, udatpg_getBestPattern, udatpg_close: a locale's pattern for a skeleton
    /// ("yMMMd").
    let openPatternGenerator: OpenPatternGenerator
    let bestPattern: BestPattern
    let closePatternGenerator: ClosePatternGenerator
    /// udat_open (with patternStyle and a pattern), udat_format.
    let openDateFormat: OpenDateFormat
    let formatDate: FormatDate

    private init?(version: Int, i18n: UnsafeMutableRawPointer) {
        func function<T>(_ library: UnsafeMutableRawPointer, _ name: String, as type: T.Type) -> T? {
            guard let symbol = dlsym(library, "\(name)_\(version)") ?? dlsym(library, name) else { return nil }
            return unsafeBitCast(symbol, to: type)
        }
        guard let openPatternGenerator = function(i18n, "udatpg_open", as: OpenPatternGenerator.self),
              let bestPattern = function(i18n, "udatpg_getBestPattern", as: BestPattern.self),
              let closePatternGenerator = function(i18n, "udatpg_close", as: ClosePatternGenerator.self),
              let openDateFormat = function(i18n, "udat_open", as: OpenDateFormat.self),
              let formatDate = function(i18n, "udat_format", as: FormatDate.self) else { return nil }
        self.version = version
        self.openPatternGenerator = openPatternGenerator
        self.bestPattern = bestPattern
        self.closePatternGenerator = closePatternGenerator
        self.openDateFormat = openDateFormat
        self.formatDate = formatDate
    }

    /// The newest ICU that opens, when it carries every function used; nil otherwise. The library
    /// stays loaded for the life of the process.
    private static func load() -> ICULibrary? {
        for version in stride(from: 120, through: 50, by: -1) {
            guard let i18n = dlopen("libicui18n.so.\(version)", RTLD_NOW | RTLD_LOCAL) else { continue }
            if let library = ICULibrary(version: version, i18n: i18n) {
                ActionUIModel.shared.logger.log("ICU \(version) formats dates by locale", .verbose)
                return library
            }
            dlclose(i18n)
            ActionUIModel.shared.logger.log("ICU \(version) lacks a function ActionUI uses; dates follow the C library's locale", .info)
            return nil
        }
        ActionUIModel.shared.logger.log("No ICU found; dates follow the C library's locale", .info)
        return nil
    }
}
