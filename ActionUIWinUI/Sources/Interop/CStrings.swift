// Sources/Interop/CStrings.swift
/*
 Swift strings as an array of C strings for one shim call (actionUIWinUIAlertShow's button titles),
 freed with the object. Keep it alive across the call (withExtendedLifetime).
*/

package final class CStrings {
    package let pointers: [UnsafePointer<CChar>?]
    private let copies: [UnsafeMutablePointer<CChar>]

    package init(_ strings: [String]) {
        copies = strings.map { text in
            let bytes = Array(text.utf8CString)
            let copy = UnsafeMutablePointer<CChar>.allocate(capacity: bytes.count)
            copy.initialize(from: bytes, count: bytes.count)
            return copy
        }
        pointers = copies.map { UnsafePointer($0) }
    }

    deinit {
        copies.forEach { $0.deallocate() }
    }
}
