/*
 ActionUIRegistry manages the registration and invocation of view-specific builders, validators, and modifiers.
 Views register their implementations via StaticElement.register<T>(registry:).
 */

import SwiftUI

class ActionUIRegistry {
    struct ViewRegistration {
        let buildElement: (ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> AnyView
        let validateProperties: ([String: Any]) -> [String: Any]
        let applyModifiers: ((AnyView, [String: Any]) -> AnyView)?
    }
    
    private var registrations: [String: ViewRegistration] = [:]
    
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
    
    func registerView(type: String, registration: ViewRegistration) {
        registrations[type] = registration
    }
    
    func validateProperties(forType type: String, properties: [String: Any]) -> [String: Any] {
        if let registration = registrations[type] {
            return registration.validateProperties(properties)
        }
        return properties // Fallback to base properties if type not registered
    }
    
    func getValidatedProperties(element: ActionUIElement, state: Binding<[Int: Any]>) -> [String: Any] {
        if state.wrappedValue[element.id] == nil {
            let baseValidated = View.validateProperties(element.properties)
            let validatedProperties = validateProperties(forType: element.type, properties: baseValidated)
            state.wrappedValue[element.id] = [
                "value": "",
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
    
    func build(for element: ActionUIElement, state: Binding<[Int: Any]>, windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
        if let registration = registrations[element.type] {
            return registration.buildElement(element, state, windowUUID, validatedProperties)
        }
        return AnyView(EmptyView())
    }
    
    func applyModifiers(to view: AnyView, properties: [String: Any], type: String) -> AnyView {
        // Step 1: Apply base View modifications
        var modifiedView = View.applyModifiers(to: view, properties: properties)
        
        // Step 2: Apply specialized view modifications if available
        if let registration = registrations[type], let applyModifiers = registration.applyModifiers {
            modifiedView = applyModifiers(modifiedView, properties)
        }
        
        return modifiedView
    }
}
