// ActionUICAdapter/ActionUIC+Windows.swift
//
//  The Windows side of hostNative (the Apple side is in ActionUIC+Apple.swift, Linux's in
//  ActionUIC+Linux.swift): Windows builds with FoundationEssentials, which has no Foundation
//  objects, so a host's values are already Swift-native.
//

#if os(Windows)
import ActionUI

/// A value a host stored, as ActionUIJSON reads it: unchanged on Windows.
func hostNative(_ value: Any) -> Any {
    value
}
#endif
