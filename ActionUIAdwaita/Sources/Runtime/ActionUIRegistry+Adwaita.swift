// Sources/Runtime/ActionUIRegistry+Adwaita.swift
/*
 The GTK renderer half of ActionUIRegistry (the SwiftUI half is
 ActionUI/Common/ActionUIRegistry+SwiftUI.swift). No element has a GTK renderer yet, so there is no
 renderer table and Core's default hooks stay.
*/

extension ActionUIRegistry {
    internal func loadRendererBuiltIns() {}
}
