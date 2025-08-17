// Common/ActionUIRegistry.swift
import SwiftUI

/*
 ActionUIRegistry manages the registration and invocation of view-specific builders, validators, and modifiers.
 Views are automatically registered during initialization of ActionUIRegistry.shared.
 The logger is client-configurable, defaulting to ConsoleLogger with verbose level.
*/

@MainActor
class ActionUIRegistry {
    // Design decision: Stores the type conforming to ActionUIViewConstruction, allowing runtime lookup of optional closure properties
    internal var registrations: [String: any ActionUIViewConstruction.Type] = [:]
    
    // Logger for validation, view building, and modifier application
    // Design decision: Client-configurable via setLogger, defaults to ConsoleLogger for consistency
    private var logger: any ActionUILogger
    
    static let shared = ActionUIRegistry()
    
    private init() {
        // Initialize with default ConsoleLogger
        self.logger = ConsoleLogger(maxLevel: .verbose)
        // Automatically register supported SwiftUI view types
        registerAllViews()
    }
    
    // Allows clients to set a custom logger (e.g., XCTestLogger)
    // Design decision: Mirrors ActionUIModel.registerActionHandler for client customization
    func setLogger(_ logger: any ActionUILogger) {
        self.logger = logger
    }
    
    // Register all supported views
    internal func registerAllViews() {
        register(AsyncImage.self)
        register(Button.self)
        register(Canvas.self)
        register(ColorPicker.self)
        register(ComboBox.self)
        register(DatePicker.self)
        register(DisclosureGroup.self)
        register(Divider.self)
        register(EmptyView.self)
        register(Form.self)
        register(Gauge.self)
        register(Grid.self)
        register(Group.self)
        register(HStack.self)
        register(Image.self)
        register(KeyframeAnimator.self)
        register(Label.self)
        register(LazyHGrid.self)
        register(LazyHStack.self)
        register(LazyVGrid.self)
        register(LazyVStack.self)
        register(Link.self)
        register(List.self)
        register(Map.self)
        register(Menu.self)
        register(NavigationLink.self)
        register(NavigationStack.self)
        register(NavigationSplitView.self)
        register(PhaseAnimator.self)
        register(Picker.self)
        register(ProgressView.self)
        register(ScrollView.self)
        register(ScrollViewReader.self)
        register(Section.self)
        register(SecureField.self)
        register(ShareLink.self)
        register(Slider.self)
        register(Spacer.self)
        register(TabBarItem.self)
        register(Table.self)
        register(Text.self)
        register(TextEditor.self)
        register(TextField.self)
        register(Toggle.self)
        register(VStack.self)
        register(VideoPlayer.self)
        register(View.self)
        register(ZStack.self)
        register(TabView.self)
        // Removed deprecated NavigationView
        // Add more view registrations if needed
    }
    
    // Registers a view construction type using its type name
    // Design decision: Simplifies registration by using String(describing: type.self), replacing StaticElement.register
    @inline(__always)
    func register(_ type: any ActionUIViewConstruction.Type) {
        registrations[String(describing: type.self)] = type
        logger.log("Registered view type: \(String(describing: type.self))", .info)
    }
    
    // Validates properties for a given element type, returning unchanged properties if type not registered
    func validateProperties(forElementType type: String, properties: [String: Any]) -> [String: Any] {
        if let constructionType = registrations[type] {
            return constructionType.validateProperties(properties, logger)
        }
        logger.log("No registration found for type \(type), returning unchanged properties", .warning)
        return properties
    }
    
    // Retrieves validated properties for an element, updating state if properties have changed
    func getValidatedProperties(element: any ActionUIElement, state: Binding<[Int: Any]>) -> [String: Any] {
        if state.wrappedValue[element.id] == nil {
            let baseValidated = View.validateProperties(element.properties, logger)
            let validatedProperties = validateProperties(forElementType: element.type, properties: baseValidated)
            state.wrappedValue[element.id] = [
                "validatedProperties": validatedProperties,
                "rawProperties": element.properties
            ]
        }
        
        let currentState = state.wrappedValue[element.id] as? [String: Any] ?? [:]
        let rawProperties = currentState["rawProperties"] as? [String: Any] ?? [:]
        let validatedProperties: [String: Any]
        
        // Compare properties using helper function
        if !PropertyComparison.arePropertiesEqual(rawProperties, element.properties) {
            let baseValidated = View.validateProperties(element.properties, logger)
            validatedProperties = validateProperties(forElementType: element.type, properties: baseValidated)
            var newState = currentState
            newState["validatedProperties"] = validatedProperties
            newState["rawProperties"] = element.properties
            state.wrappedValue[element.id] = newState
        } else {
            validatedProperties = currentState["validatedProperties"] as? [String: Any] ?? validateProperties(forElementType: element.type, properties: View.validateProperties(element.properties, logger))
        }
        
        return validatedProperties
    }
    
    // Retrieves the value type for a given view element type
    // Design decision: Returns Void if valueType is not implemented, ensuring compatibility with non-interactive views
    func getElementValueType(forElementType type: String) -> Any.Type {
        return registrations[type]?.valueType ?? Void.self
    }
    
    // Builds a SwiftUI view for an element, only passing validatedProperties, leaving value and view-specific state to buildView
    func buildView(for element: any ActionUIElement, state: Binding<[Int: Any]>, windowUUID: String, validatedProperties: [String: Any]) -> any SwiftUI.View {
        // Initialize shared state if not present
        // Design decision: Ensures all views have validatedProperties, with value and view-specific state handled by buildView
        if state.wrappedValue[element.id] == nil {
            state.wrappedValue[element.id] = [
                "validatedProperties": validatedProperties
            ]
        }
        
        if let constructionType = registrations[element.type] {
            return constructionType.buildView(element, state, windowUUID, validatedProperties, logger)
        }
        logger.log("No construction type found for \(element.type), returning EmptyView", .warning)
        return SwiftUI.EmptyView()
    }
    
    // Applies modifiers to a view, using a Binding to state for dynamic updates
    // Design decision: Binds to validatedProperties in state to support dynamic property changes (e.g., disabled) via setProperty, ensuring SwiftUI refreshes
    // Applies baseline View modifiers first, then view-specific modifiers, per the guide's modifier separation principle
    func applyModifiers(to view: any SwiftUI.View, properties: [String: Any], element: any ActionUIElement, state: Binding<[Int: Any]>) -> AnyView {
        // Bind to validatedProperties in state, falling back to provided properties
        // Design decision: Binding ensures dynamic updates (e.g., for baseline properties like disabled) trigger view refreshes without re-rendering the entire hierarchy
        let validatedPropertiesBinding = Binding(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["validatedProperties"] as? [String: Any] ?? properties },
            set: { state.wrappedValue[element.id] = (state.wrappedValue[element.id] as? [String: Any] ?? [:]).merging(["validatedProperties": $0], uniquingKeysWith: { $1 }) }
        )
        
        // Step 1: Apply base View modifications dynamically
        // Design decision: Delegates baseline modifiers (e.g., padding, disabled, hidden) to View.applyModifiers to centralize shared logic
        var modifiedView = View.applyModifiers(view, validatedPropertiesBinding.wrappedValue, logger)
        
        // Step 2: Apply specialized view modifications if available
        if let constructionType = registrations[element.type] {
            modifiedView = constructionType.applyModifiers(modifiedView, validatedPropertiesBinding.wrappedValue, logger)
        }
        return AnyView(modifiedView)
    }
}

