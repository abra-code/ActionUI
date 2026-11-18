// Sources/Runtime/ActionUIRegistry+WinUI.swift
/*
 The WinUI renderer's half of ActionUIRegistry. The renderer has no elements yet, so it registers
 none: ActionUI/Core and its specs load on their own, as in the core-check package
 (ActionUICoreCheck). The elements come with the renderer runtime.
*/

extension ActionUIRegistry {
    internal func loadRendererBuiltIns() {}
}
