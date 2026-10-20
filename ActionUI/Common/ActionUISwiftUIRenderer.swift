// Common/ActionUISwiftUIRenderer.swift
/*
 How an element type draws with SwiftUI. An element type is its spec (ActionUIElementSpec, shared
 by every renderer) plus this renderer; ActionUIViewConstruction names the two together, which is
 what a built-in element or an add-on element type implements on Apple.
*/

import SwiftUI

@MainActor
public protocol ActionUISwiftUIRenderer {
    static var buildView: ((any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View) { get }
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View { get }
}

/// An element type on Apple: its spec and its SwiftUI renderer.
public typealias ActionUIViewConstruction = ActionUIElementSpec & ActionUISwiftUIRenderer
