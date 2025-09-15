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
    // Design decision: Simplifies registration by using String(describing: type.self), replacing ViewElement.register
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
    
    // Retrieves validated properties for an element, using cached validatedProperties if available
    func getValidatedProperties(element: any ActionUIElement, model: ViewModel) -> [String: Any] {
        if !model.validatedProperties.isEmpty {
            return model.validatedProperties
        }
        let baseValidated = View.validateProperties(element.properties, logger)
        return validateProperties(forElementType: element.type, properties: baseValidated)
    }
    
    // Retrieves the value type for a given view element type
    // Design decision: Returns Void if valueType is not implemented, ensuring compatibility with non-interactive views
    func getElementValueType(forElementType type: String) -> Any.Type {
        return registrations[type]?.valueType ?? Void.self
    }
    
    func getInitialValue(forElementType type: String, model: ViewModel) -> Any? {
        if let constructionType = registrations[type],
           constructionType.valueType != Void.self {
            let initialValue = constructionType.initialValue(model)
            if initialValue == nil,
               constructionType.valueType != Double?.self { //any optional value type mat be nil
                logger.log("Inital value not provided for element of type \(type), which declares non-void valueType", .error)
            }
            return initialValue
        }
        return nil
    }
    
    // Builds a SwiftUI view for an element, only passing validatedProperties, leaving value and view-specific state to buildView
    func buildView(for element: any ActionUIElement, model: ViewModel, windowUUID: String, validatedProperties: [String: Any]) -> any SwiftUI.View {
        // Initialize shared state if not present
        // Design decision: Ensures all views have validatedProperties, with value and view-specific state handled by buildView
        if model.validatedProperties.isEmpty {
            model.validatedProperties = validatedProperties
        }
        
        if let constructionType = registrations[element.type] {
            return constructionType.buildView(element, model, windowUUID, validatedProperties, logger)
        }
        logger.log("No construction type found for element ID \(element.id) of type '\(element.type)' in window \(windowUUID), returning EmptyView", .warning)
        
        return SwiftUI.EmptyView()
    }
    
    // Applies modifiers to a view, using a ViewModel for dynamic updates
    // Design decision: Uses validatedProperties in model to support dynamic property changes (e.g., disabled) via setProperty, ensuring SwiftUI refreshes
    // Applies baseline View modifiers first, then view-specific modifiers, per the guide's modifier separation principle
    func applyModifiers(to view: any SwiftUI.View, properties: [String: Any], element: any ActionUIElement, model: ViewModel) -> AnyView {
        
        var modifiedView = view
        // First apply specialized view modifications if available (View.applyModifiers can erase specific view type)
        if let constructionType = registrations[element.type] {
            modifiedView = constructionType.applyModifiers(modifiedView, properties, logger)
        } else {
            logger.log("No modifier registration found for element ID \(element.id) of type '\(element.type)', applying base modifiers only", .warning)
        }
        
        // Apply base View modifications dynamically
        // Design decision: Delegates baseline modifiers (e.g., padding, disabled, hidden) to View.applyModifiers to centralize shared logic
        modifiedView = View.applyModifiers(view, properties, logger)

        return AnyView(modifiedView)
    }
}
