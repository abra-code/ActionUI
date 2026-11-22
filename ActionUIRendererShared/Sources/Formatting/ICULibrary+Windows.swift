// Sources/Formatting/ICULibrary+Windows.swift
/*
 Finding ICU on Windows. Windows 10 1903 and later carry ICU as a system DLL, icu.dll in System32 (ICU's
 common and i18n parts in one library), whose C functions have their plain names, without the version
 suffix Linux's carry. It is loaded from System32 only, never a DLL of that name beside the program.
 ICU's major version comes from its u_getVersion, as the DLL's name has none. ActionUI's floor is
 Windows 11, which has it; without it (a trimmed system image) dates follow Windows' short formats and
 numbers show plain digits.
*/

#if os(Windows)

import WinSDK

extension ICULibrary {
    /// Windows' ICU, when it carries every function used; nil otherwise. The library stays loaded for the
    /// life of the process.
    static func load() -> ICULibrary? {
        let module = "icu.dll".withCString(encodedAs: UTF16.self) { LoadLibraryExW($0, nil, DWORD(LOAD_LIBRARY_SEARCH_SYSTEM32)) }
        guard let module else {
            ActionUIModel.shared.logger.log("No ICU (icu.dll) found; dates follow Windows' short formats and numbers show plain digits", .info)
            return nil
        }
        func lookup(_ name: String) -> UnsafeMutableRawPointer? {
            guard let address = GetProcAddress(module, name) else { return nil }
            return unsafeBitCast(address, to: UnsafeMutableRawPointer.self)
        }
        // u_getVersion fills ICU's UVersionInfo: four bytes, the major version first.
        typealias GetVersion = @convention(c) (UnsafeMutablePointer<UInt8>?) -> Void
        var version = 0
        if let symbol = lookup("u_getVersion") {
            var info = [UInt8](repeating: 0, count: 4)
            info.withUnsafeMutableBufferPointer { buffer in
                unsafeBitCast(symbol, to: GetVersion.self)(buffer.baseAddress)
            }
            version = Int(info[0])
        }
        if let library = ICULibrary(version: version, symbol: lookup) {
            ActionUIModel.shared.logger.log("ICU \(version) (icu.dll) formats dates and numbers by locale", .verbose)
            return library
        }
        _ = FreeLibrary(module)
        ActionUIModel.shared.logger.log("ICU (icu.dll) lacks a function ActionUI uses; dates follow Windows' short formats and numbers show plain digits", .info)
        return nil
    }
}

#endif
