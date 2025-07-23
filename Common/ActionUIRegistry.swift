/*
 ActionUIRegistry manages the registration and invocation of view-specific builders, validators, and modifiers.
 Views register their implementations via StaticElement.register<T>(registry:).
 */

import SwiftUI

class ActionUIRegistry {
    // Design decision: Stores the type conforming to ActionUIViewConstruction, allowing runtime lookup of optional closure properties
    private var registrations: [String: any ActionUIViewConstruction.Type] = [:]
    
    static let shared = ActionUIRegistry()
    
    private init() {
        // No initial registrations; rely on external calls
    }
    
    func setupActionUIRegistry() {
        let registry = ActionUIRegistry.shared
        
        StaticElement.register<AsyncImage>(registry: registry)
        StaticElement.register<Button>(registry: registry)
        StaticElement.register<Canvas>(registry: registry)
        StaticElement.register<ColorPicker>(registry: registry)
        StaticElement.register<ComboBox>(registry: registry)
        StaticElement.register<DatePicker>(registry: registry)
        StaticElement.register<DisclosureGroup>(registry: registry)
        StaticElement.register<Divider>(registry: registry)
        StaticElement.register<EmptyView>(registry: registry)
        StaticElement.register<Form>(registry: registry)
        StaticElement.register<Gauge>(registry: registry)
        StaticElement.register<Grid>(registry: registry)
        StaticElement.register<Group>(registry: registry)
        StaticElement.register<HStack>(registry: registry)
        StaticElement.register<Image>(registry: registry)
        StaticElement.register<KeyframeAnimator>(registry: registry)
        StaticElement.register<Label>(registry: registry)
        StaticElement.register<LazyHGrid>(registry: registry)
        StaticElement.register<LazyHStack>(registry: registry)
        StaticElement.register<LazyVGrid>(registry: registry)
        StaticElement.register<LazyVStack>(registry: registry)
        StaticElement.register<Link>(registry: registry)
        StaticElement.register<List>(registry: registry)
        StaticElement.register<Map>(registry: registry)
        StaticElement.register<Menu>(registry: registry)
        StaticElement.register<NavigationLink>(registry: registry)
        StaticElement.register<NavigationView>(registry: registry)
        StaticElement.register<PhaseAnimator>(registry: registry)
        StaticElement.register<Picker>(registry: registry)
        StaticElement.register<ProgressView>(registry: registry)
        StaticElement.register<ScrollView>(registry: registry)
        StaticElement.register<ScrollViewReader>(registry: registry)
        StaticElement.register<Section>(registry: registry)
        StaticElement.register<SecureField>(registry: registry)
        StaticElement.register<ShareLink>(registry: registry)
        StaticElement.register<Slider>(registry: registry)
        StaticElement.register<Spacer>(registry: registry)
        StaticElement.register<StepSlider>(registry: registry)
        StaticElement.register<TabBarItem>(registry: registry)
        StaticElement.register<Table>(registry: registry)
        StaticElement.register<TabView>(registry: registry)
        StaticElement.register<Text>(registry: registry)
        StaticElement.register<TextEditor>(registry: registry)
        StaticElement.register<TextField>(registry: registry)
        StaticElement.register<Toggle>(registry: registry)
        StaticElement.register<VideoPlayer>(registry: registry)
        StaticElement.register<View>(registry: registry)
        StaticElement.register<VStack>(registry: registry)
        StaticElement.register<ZStack>(registry: registry)
        // Add additional view classes as needed with proper implementations
    }
    
    // Design decision: Registers the type conforming to ActionUIViewConstruction, using optional closure properties with defaults
    func registerView(type: String, constructionType: any ActionUIViewConstruction.Type) {
        registrations[type] = constructionType
    }
    
    func validateProperties(forType type: String, properties: [String: Any]) -> [String: Any] {
        if let constructionType = registrations[type],
           let validate = constructionType.validateProperties {
            return validate(properties)
        }
        return properties // Fallback to base properties if type not registered or validateProperties is nil
    }
    
    func getValidatedProperties(element: ActionUIElement, state: Binding<[Int: Any]>) -> [String: Any] {
        if state.wrappedValue[element.id] == nil {
            let baseValidated = View.validateProperties(element.properties)
            let validatedProperties = validateProperties(forType: element.type, properties: baseValidated)
            state.wrappedValue[element.id] = [
                "validatedProperties": validatedProperties,
                "rawProperties": element.properties
            ]
        }
        
        let currentState = state.wrappedValue[element.id] as? [String: Any] ?? [:]
        let rawProperties = currentState["rawProperties"] as? [String: Any] ?? [:]
        let validatedProperties: [String: Any]
        
        if rawProperties != element.properties {
            let baseValidated = View.validateProperties(element.properties)
            validatedProperties = validateProperties(forType: element.type, properties: baseValidated)
            var newState = currentState
            newState["validatedProperties"] = validatedProperties
            newState["rawProperties"] = element.properties
            state.wrappedValue[element.id] = newState
        } else {
            validatedProperties = currentState["validatedProperties"] as? [String: Any] ?? validateProperties(forType: element.type, properties: View.validateProperties(element.properties))
        }
        
        return validatedProperties
    }
    
    // Retrieves the value type for a given view type
    // Design decision: Returns Void if valueType is not implemented, ensuring compatibility with non-interactive views
    func getValueType(forType type: String) -> Any.Type? {
        return registrations[type]?.valueType ?? Void.self
    }
    
    // Builds a view for the given element, initializing shared state
    // Design decision: Initializes only validatedProperties, leaving value and view-specific state to buildElement
    func build(for element: ActionUIElement, state: Binding<[Int: Any]>, windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
        // Initialize shared state if not present
        // Design decision: Ensures all views have validatedProperties, with value and view-specific state handled by buildElement
        if state.wrappedValue[element.id] == nil {
            state.wrappedValue[element.id] = [
                "validatedProperties": validatedProperties
            ]
        }
        
        if let constructionType = registrations[element.type],
           let build = constructionType.buildElement {
            return build(element, state, windowUUID, validatedProperties)
        }
        return AnyView(EmptyView())
    }
    
    // Applies modifiers to a view, using a Binding to state for dynamic updates
    // Design decision: Binds to validatedProperties in state to support dynamic property changes (e.g., disabled) via setProperty, ensuring SwiftUI refreshes
    // Applies baseline View modifiers first, then view-specific modifiers, per the guide's modifier separation principle
    func applyModifiers(to view: AnyView, properties: [String: Any], element: ActionUIElement, state: Binding<[Int: Any]>) -> AnyView {
        // Bind to validatedProperties in state, falling back to provided properties
        // Design decision: Binding ensures dynamic updates (e.g., for baseline properties like disabled) trigger view refreshes without re-rendering the entire hierarchy
        let validatedPropertiesBinding = Binding(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["validatedProperties"] as? [String: Any] ?? properties },
            set: { state.wrappedValue[element.id] = (state.wrappedValue[element.id] as? [String: Any] ?? [:]).merging(["validatedProperties": $0], uniquingKeysWith: { $1 }) }
        )
        
        // Step 1: Apply base View modifications dynamically
        // Design decision: Delegates baseline modifiers (e.g., padding, disabled, hidden) to View.applyModifiers to centralize shared logic
        var modifiedView = View.applyModifiers(to: view, properties: validatedPropertiesBinding.wrappedValue)
        
        // Step 2: Apply specialized view modifications if available
        if let constructionType = registrations[element.type],
           let applyModifiers = constructionType.applyModifiers {
            modifiedView = applyModifiers(modifiedView, validatedPropertiesBinding.wrappedValue)
        }
        
        return modifiedView
    }
}
