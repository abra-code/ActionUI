// ActionUICAdapter/ActionUIC+Linux.swift
//
//  The Linux side of hostNative (the Apple side is in ActionUIC+Apple.swift). Linux builds with
//  FoundationEssentials, which has no Foundation objects, so a host's values are already
//  Swift-native.
//

/// A value a host stored, as ActionUIJSON reads it: unchanged on Linux.
func hostNative(_ value: Any) -> Any {
    value
}
