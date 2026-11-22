// ActionUICoreCheck/DateFormatting+CoreCheck.swift
/*
 DateFormatting's fallback without ICU for the Core-only check package (Package.swift,
 coreCheckPackage), which has no renderer: no text. The GTK renderer's is GLib's
 (ActionUIAdwaita/Sources/Formatting/DateFormatting+GLib.swift). Windows' (on the WinUI branch)
 needs no toolkit, so it sits in the shared code beside DateFormatting and this one is left out.
*/

#if !os(Windows)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension DateFormatting {
    static func fallbackString(_ date: Date, skeleton: String, timeZone: String?) -> String {
        ""
    }
}

#endif
