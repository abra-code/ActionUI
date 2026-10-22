// ActionUICoreCheck/ActionUIRegistry+CoreCheck.swift
/*
 The renderer half of ActionUIRegistry for the Core-only check package (Package.swift,
 coreCheckPackage): no renderers and no hooks, so ActionUI/Core builds and its specs load on their
 own. Each real renderer provides its own loadRendererBuiltIns (GTK:
 ActionUIAdwaita/Sources/Runtime/ActionUIRegistry+Adwaita.swift; SwiftUI:
 ActionUI/Common/ActionUIRegistry+SwiftUI.swift).
*/

extension ActionUIRegistry {
    internal func loadRendererBuiltIns() {}
}
