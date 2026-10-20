// Core/Common/ActionUIElementSpec.swift
/*
 What an element type is, apart from how it draws: the type of its value, its initial value and
 states, its string conversions, the containers that accept runtime insertions, and how it reacts
 to a property change. Every renderer shares it; each renderer adds the drawing in its own
 protocol (ActionUISwiftUIRenderer on Apple).

 Public so optional add-on libraries (linked against ActionUI) can implement a custom element type
 and register it via ActionUIRegistry.register(_:as:). Built-in elements conform internally;
 external conformers use only the public surface (element, ViewModel value/states,
 ActionUIModel.actionHandler, logger).
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@MainActor
public protocol ActionUIElementSpec {
    static var valueType: Any.Type { get }
    static var initialValue: (ViewModel) -> Any? { get }
    static var initialStates: (ViewModel) -> [String: Any] { get }
    // Optional content-type hooks for rich-text views.
    // parseStringValue: convert a string + content-type token -> typed value (nil = fall through to generic switch)
    // serializeValueToString: convert a typed value + content-type token -> string (nil = fall through to generic logic)
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? { get }
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? { get }
    // Containers that accept runtime insertions via ActionUIModel.insertElement / insertRow.
    // Map from container key (e.g. "children", "destinations", "rows") to its shape.
    // nil or empty for an element that is not a container: it rejects insertions.
    static var insertableContainers: [String: ContainerShape]? { get }
    // Called by ActionUIModel.setElementProperty after it stores a property,
    // with the property name and the view model. Lets an element react to a runtime property
    // change beyond re-rendering (Chart moves a new description's inline data into its rows).
    // Default nil.
    static var didSetProperty: ((String, ViewModel, any ActionUILogger) -> Void)? { get }
    // Base View property keys (for example "cornerRadius") that the element applies itself, in its
    // renderer. ActionUIRegistry.applyViewModifiers leaves them out of the base View modifiers, so
    // they are not applied twice; the element still receives them in its own properties. Only that
    // registry path honors it: a direct call to View.applyModifiers does not.
    // Default: none.
    static var handledBaseModifiers: Set<String> { get }
}

extension ActionUIElementSpec {
    public static var didSetProperty: ((String, ViewModel, any ActionUILogger) -> Void)? { nil }
    public static var handledBaseModifiers: Set<String> { [] }
}
