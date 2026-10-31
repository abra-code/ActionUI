// Tests/AddOnFixture/FixtureBadge.swift
/*
 An element written as an add-on writes one, in a module of its own that imports ActionUI without
 @testable: that this compiles shows the public contract is enough for an add-on. A label showing
 the runtime value, else the "text" property, with the "prefix" state before it; `update` also
 reads `suffix`, a value the model cannot report, which is why `refresh` calls setNeedsUpdate().
 What the tests need from the contract goes through this module (register, refresh, seenType,
 seenWindow), as the tests themselves see internals with @testable.
*/

import ActionUI
import CAdwaita

public final class FixtureKept {
    public init() {}
}

public struct FixtureBadge: ActionUIAdwaitaElement {
    /// The node of the badge last made, and how often update ran, for the tests.
    public static var node: RenderNode?
    public static var updates = 0
    /// What the badge last made keeps, seen weakly: it goes with its node.
    public private(set) static weak var kept: FixtureKept?
    /// What update last read from the node's element and window.
    public static var seenType = ""
    public static var seenWindow = ""
    /// Text from outside the model, as an image arriving is for a real add-on.
    public static var suffix = ""

    /// The add-on's entry point, which the host calls at launch.
    public static func register() {
        ActionUIRegistry.shared.register(FixtureBadge.self, as: "FixtureBadge")
    }

    /// `suffix` changed: as a real add-on does when its image arrives.
    public static func refresh() {
        node?.setNeedsUpdate()
    }

    public static var valueType: Any.Type { String.self }
    public static var initialValue: (ViewModel) -> Any? { { ($0.value as? String) ?? "" } }
    public static var initialStates: (ViewModel) -> [String: Any] {
        { model in
            var states = model.states
            if states["prefix"] == nil {
                states["prefix"] = ""
            }
            return states
        }
    }
    public static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? { nil }
    public static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? { nil }
    public static var insertableContainers: [String: ContainerShape]? { nil }
    /// The badge applies "opacity" itself, in `update`.
    public static var handledBaseModifiers: Set<String> { ["opacity"] }

    public static func makeWidget(_ node: RenderNode) -> OpaquePointer {
        self.node = node
        let kept = FixtureKept()
        node.state = kept
        self.kept = kept
        return OpaquePointer(gtk_label_new(nil)!)
    }

    public static func update(_ widget: OpaquePointer, _ node: RenderNode) {
        updates += 1
        seenType = node.element.type
        seenWindow = node.windowUUID
        let value = (node.model.value as? String).flatMap { $0.isEmpty ? nil : $0 }
        let text = value ?? (node.properties["text"] as? String) ?? ""
        let prefix = node.model.states["prefix"] as? String ?? ""
        gtk_label_set_text(widget, prefix + text + suffix)
        gtk_widget_set_opacity(UnsafeMutablePointer(widget), node.properties["opacity"] as? Double ?? 1)
    }

    /// A second element under the same token, to show that a later registration replaces the first.
    public struct Replacement: ActionUIAdwaitaElement {
        public static var valueType: Any.Type { String.self }
        public static var initialValue: (ViewModel) -> Any? { { _ in "" } }
        public static var initialStates: (ViewModel) -> [String: Any] { { $0.states } }
        public static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? { nil }
        public static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? { nil }
        public static var insertableContainers: [String: ContainerShape]? { nil }

        public static func makeWidget(_ node: RenderNode) -> OpaquePointer {
            OpaquePointer(gtk_label_new("replacement")!)
        }

        public static func update(_ widget: OpaquePointer, _ node: RenderNode) {}
    }
}
