// Core/Common/ActionUIRegistry.swift
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/*
 ActionUIRegistry holds every element type's spec and answers what a document load needs (value
 type, initial value and states, string conversions, insertable containers). The renderer half
 (SwiftUI: Common/ActionUIRegistry+SwiftUI.swift) holds the renderer table and builds views.
 Built-in elements are loaded during initialization of ActionUIRegistry.shared.
 The logger is client-configurable, defaulting to ConsoleLogger with verbose level.
*/

@MainActor
public class ActionUIRegistry {
    // Each element type's spec, keyed by the JSON "type" token. It answers everything a document
    // load needs (value type, initial value and states, string conversions, insertable containers);
    // the renderer table, keyed the same way, is in the renderer half.
    internal var specs: [String: any ActionUIElementSpec.Type] = [:]
    
    // Logger for view building and modifier application
    // Design decision: Client-configurable via setLogger, defaults to ConsoleLogger for consistency
    private(set) var logger: any ActionUILogger
    
    public static let shared = ActionUIRegistry()

    /// Selects which backing renders WebView elements. Host apps set this once at launch
    /// (before windows are built). Defaults to `.native`, which works on the package baseline
    /// (macOS 14.6+ / iOS 17.6+); `.swiftUI` uses SwiftUI's WebKit.WebView (requires OS 26).
    public var webViewImplementation: WebViewImplementation = .native

    private init() {
        // Initialize with default ConsoleLogger
        var loggerLevel: LoggerLevel = .warning
#if DEBUG
        loggerLevel = .info
#endif
        self.logger = ConsoleLogger(maxLevel: loggerLevel)
        loadBuiltIns()
    }
    
    // Allows clients to set a custom logger (e.g., XCTestLogger)
    // Design decision: Mirrors ActionUIModel.registerActionHandler for client customization
    public func setLogger(_ logger: any ActionUILogger) {
        self.logger = logger
    }
    
    // Fills the spec table with the portable built-in element types
    // (Core/Elements/BuiltInElements.swift), then lets the renderer half add its own built-ins
    // (loadRendererBuiltIns: its renderer table, any element types it still keeps to itself, and
    // its hooks). Replaces both tables, so it runs before any add-on registers (at init, and in the
    // tests' reset).
    internal func loadBuiltIns() {
        specs = Dictionary(uniqueKeysWithValues: Self.builtInSpecs.map { ($0.name, $0.type) })
        loadRendererBuiltIns()
    }
    
    // An element's current properties: its view model's store once seeded (by a load or a template
    // row), else the element's own. Never writes: a write during a view body would be a model
    // mutation inside a render.
    func currentProperties(element: any ActionUIElementBase, model: ViewModel) -> [String: Any] {
        model.hasProperties ? model.properties : element.properties
    }
    
    // Retrieves the value type for a given view element type
    // Design decision: Returns Void if valueType is not implemented, ensuring compatibility with non-interactive views
    func getElementValueType(forElementType type: String) -> Any.Type {
        let valueType = specs[type]?.valueType ?? Void.self
        return getNonOptionalType(valueType)
    }
    
    func getInitialValue(forElementType type: String, model: ViewModel) -> Any? {
        if let constructionType = specs[type],
           constructionType.valueType != Void.self {
            let initialValue = constructionType.initialValue(model)
            if initialValue == nil,
                !isOptional(constructionType.valueType) { //any optional value type may be nil
                logger.log("Inital value not provided for element of type \(type), which declares non-void valueType", .error)
            }
            return initialValue
        }
        return nil
    }
    
    func getStringContentParser(forElementType type: String) -> ((String, String?, any ActionUILogger) -> Any?)? {
        specs[type]?.parseStringValue
    }

    func getStringContentSerializer(forElementType type: String) -> ((Any, String?, any ActionUILogger) -> String?)? {
        specs[type]?.serializeValueToString
    }

    func getDidSetProperty(forElementType type: String) -> ((String, ViewModel, any ActionUILogger) -> Void)? {
        specs[type]?.didSetProperty
    }

    func getInitialStates(forElementType type: String, model: ViewModel) -> [String: Any] {
        if let constructionType = specs[type] {
            return constructionType.initialStates(model)
        }
        return [:]
    }
    
    // Returns a copy of the element with `model.dynamicSubviews` merged over its static subviews.
    // Returns the original element unchanged when there are no dynamic mutations or when the
    // element is not a concrete ActionUIElement (cannot rebuild non-concrete protocol values).
    func applyDynamicSubviews(to element: any ActionUIElementBase, model: ViewModel) -> any ActionUIElementBase {
        guard let dynamic = model.dynamicSubviews, !dynamic.isEmpty else { return element }
        guard let concrete = element as? ActionUIElement else { return element }
        var merged = concrete.subviews ?? [:]
        for (key, value) in dynamic { merged[key] = value }
        return ActionUIElement(id: concrete.id, type: concrete.type, properties: concrete.properties, subviews: merged)
    }

    // Returns the insertable container map for a registered view type
    func getInsertableContainers(forElementType type: String) -> [String: ContainerShape]? {
        specs[type]?.insertableContainers
    }
    
    // The properties the base View modifiers apply for an element: all of them, minus the keys the
    // element's type declares in handledBaseModifiers (it applies those itself).
    func baseModifierProperties(_ properties: [String: Any], forElementType type: String) -> [String: Any] {
        guard let handled = specs[type]?.handledBaseModifiers, !handled.isEmpty else {
            return properties
        }
        return properties.filter { !handled.contains($0.key) }
    }
}
