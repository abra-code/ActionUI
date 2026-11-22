// Sources/Formatting/ICULibrary.swift
/*
 The system's ICU (International Components for Unicode), found and loaded at run time, for
 formatting dates and numbers by the user's locale: FoundationEssentials cannot do that, and full
 Foundation would bring 45 MB of ICU data into every program. Each platform finds its ICU in a file
 of its own (Linux: ICULibrary+Linux.swift), which gives the initializer a lookup for the functions'
 addresses. A missing function disables ICU as a whole, as does no library at all; callers then
 fall back to the platform's own date format (DateFormatting) or to plain digits (NumberFormatting).

 No ICU header is used: the few C types are declared here (UChar is UInt16, UErrorCode Int32, UDate
 Double milliseconds, the opened objects opaque pointers), with the values the formatters need
 taken from the ICU 76 headers; these values do not change between ICU versions.
*/

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
    typealias OpenCalendar = @convention(c) (UnsafePointer<UInt16>?, Int32, UnsafePointer<CChar>?, Int32, UnsafeMutablePointer<ErrorCode>?) -> OpaquePointer?
    typealias CalendarAttribute = @convention(c) (OpaquePointer?, Int32) -> Int32
    typealias CloseCalendar = @convention(c) (OpaquePointer?) -> Void
    typealias OpenNumberFormat = @convention(c) (Int32, UnsafePointer<UInt16>?, Int32, UnsafePointer<CChar>?, OpaquePointer?,
                                                 UnsafeMutablePointer<ErrorCode>?) -> OpaquePointer?
    typealias SetNumberAttribute = @convention(c) (OpaquePointer?, Int32, Int32) -> Void
    typealias SetNumberTextAttribute = @convention(c) (OpaquePointer?, Int32, UnsafePointer<UInt16>?, Int32,
                                                       UnsafeMutablePointer<ErrorCode>?) -> Void
    typealias FormatNumber = @convention(c) (OpaquePointer?, Double, UnsafeMutablePointer<UInt16>?, Int32, OpaquePointer?,
                                             UnsafeMutablePointer<ErrorCode>?) -> Int32
    typealias ParseNumber = @convention(c) (OpaquePointer?, UnsafePointer<UInt16>?, Int32, UnsafeMutablePointer<Int32>?,
                                            UnsafeMutablePointer<ErrorCode>?) -> Double

    /// U_ZERO_ERROR; an ICU call failed when its status is above it (warnings are below).
    static let noError: ErrorCode = 0
    /// UDAT_PATTERN, the style that tells udat_open to use the pattern it is given.
    static let patternStyle: Int32 = -2
    /// UCAL_GREGORIAN, the calendar type for ucal_open, and UCAL_FIRST_DAY_OF_WEEK, the
    /// UCalendarAttribute giving the day a week starts on, 1 for Sunday as Calendar counts.
    static let gregorianCalendar: Int32 = 1, firstDayOfWeek: Int32 = 1
    /// UNumberFormatStyle values for unum_open.
    static let decimalStyle: Int32 = 1, currencyStyle: Int32 = 2, percentStyle: Int32 = 3
    /// UNumberFormatAttribute values for unum_setAttribute.
    static let maxFractionDigits: Int32 = 6, minFractionDigits: Int32 = 7, lenientParse: Int32 = 19
    /// UNUM_CURRENCY_CODE, the UNumberFormatTextAttribute naming a currency formatter's currency.
    static let currencyCode: Int32 = 5

    /// The loaded ICU, or nil when none was found (or a test disabled it). The platform's file
    /// gives `load()`, asked once.
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
    /// ucal_open, ucal_getAttribute, ucal_close: a locale's calendar.
    let openCalendar: OpenCalendar
    let calendarAttribute: CalendarAttribute
    let closeCalendar: CloseCalendar
    /// unum_open, unum_setAttribute, unum_setTextAttribute, unum_formatDouble,
    /// unum_parseDouble: a locale's number formats.
    let openNumberFormat: OpenNumberFormat
    let setNumberAttribute: SetNumberAttribute
    let setNumberTextAttribute: SetNumberTextAttribute
    let formatNumber: FormatNumber
    let parseNumber: ParseNumber

    /// Each function's address comes from `symbol`, given its plain ICU name ("udat_format"); nil
    /// when one is missing. `version` is ICU's major version.
    init?(version: Int, symbol: (String) -> UnsafeMutableRawPointer?) {
        func function<T>(_ name: String, as type: T.Type) -> T? {
            guard let address = symbol(name) else { return nil }
            return unsafeBitCast(address, to: type)
        }
        guard let openPatternGenerator = function("udatpg_open", as: OpenPatternGenerator.self),
              let bestPattern = function("udatpg_getBestPattern", as: BestPattern.self),
              let closePatternGenerator = function("udatpg_close", as: ClosePatternGenerator.self),
              let openDateFormat = function("udat_open", as: OpenDateFormat.self),
              let formatDate = function("udat_format", as: FormatDate.self),
              let openCalendar = function("ucal_open", as: OpenCalendar.self),
              let calendarAttribute = function("ucal_getAttribute", as: CalendarAttribute.self),
              let closeCalendar = function("ucal_close", as: CloseCalendar.self),
              let openNumberFormat = function("unum_open", as: OpenNumberFormat.self),
              let setNumberAttribute = function("unum_setAttribute", as: SetNumberAttribute.self),
              let setNumberTextAttribute = function("unum_setTextAttribute", as: SetNumberTextAttribute.self),
              let formatNumber = function("unum_formatDouble", as: FormatNumber.self),
              let parseNumber = function("unum_parseDouble", as: ParseNumber.self) else { return nil }
        self.version = version
        self.openPatternGenerator = openPatternGenerator
        self.bestPattern = bestPattern
        self.closePatternGenerator = closePatternGenerator
        self.openDateFormat = openDateFormat
        self.formatDate = formatDate
        self.openCalendar = openCalendar
        self.calendarAttribute = calendarAttribute
        self.closeCalendar = closeCalendar
        self.openNumberFormat = openNumberFormat
        self.setNumberAttribute = setNumberAttribute
        self.setNumberTextAttribute = setNumberTextAttribute
        self.formatNumber = formatNumber
        self.parseNumber = parseNumber
    }
}
