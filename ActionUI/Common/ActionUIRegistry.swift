// Common/ActionUIRegistry.swift
import SwiftUI

/*
 ActionUIRegistry manages the registration and invocation of view-specific builders, validators, and modifiers.
 Views are automatically registered during initialization of ActionUIRegistry.shared.
 The logger is client-configurable, defaulting to ConsoleLogger with verbose level.
*/

@MainActor
public class ActionUIRegistry {
    // Design decision: Stores the type conforming to ActionUIViewConstruction, allowing runtime lookup of optional closure properties
    internal var viewRegistrations: [String: any ActionUIViewConstruction.Type] = [:]
    // for other non-View elements we register validation only
    internal var validationRegistrations: [String: any ActionUIPropertyValidation.Type] = [:]
    
    // Logger for validation, view building, and modifier application
    // Design decision: Client-configurable via setLogger, defaults to ConsoleLogger for consistency
    private var logger: any ActionUILogger
    
    public static let shared = ActionUIRegistry()
    
    private init() {
        // Initialize with default ConsoleLogger
        var loggerLevel: LoggerLevel = .warning
#if DEBUG
        loggerLevel = .info
#endif
        self.logger = ConsoleLogger(maxLevel: loggerLevel)
        // Automatically register supported SwiftUI view types
        registerAllViews()
        registerAdditionalElementValidations()
    }
    
    // Allows clients to set a custom logger (e.g., XCTestLogger)
    // Design decision: Mirrors ActionUIModel.registerActionHandler for client customization
    public func setLogger(_ logger: any ActionUILogger) {
        self.logger = logger
    }
    
    // Register all supported views
    internal func registerAllViews() {
        registerView(AsyncImage.self)
        registerView(Button.self)
        registerView(Canvas.self)
        registerView(ColorPicker.self)
        registerView(ControlGroup.self)
        registerView(DatePicker.self)
        registerView(DisclosureGroup.self)
        registerView(Divider.self)
        registerView(EmptyView.self)
        registerView(Form.self)
        registerView(Gauge.self)
        registerView(GeometryReader.self)
        registerView(Grid.self)
        registerView(Group.self)
        registerView(GroupBox.self)
        registerView(HStack.self)
        registerView(Image.self)
        registerView(KeyframeAnimator.self)
        registerView(Label.self)
        registerView(ActionUI.LabeledContent.self)
        registerView(LazyHGrid.self)
        registerView(LazyHStack.self)
        registerView(LazyVGrid.self)
        registerView(LazyVStack.self)
        registerView(Link.self)
        registerView(List.self)
        registerView(LoadableView.self)
        registerView(Map.self)
        registerView(Menu.self)
        registerView(NavigationLink.self)
        registerView(NavigationStack.self)
        registerView(NavigationSplitView.self)
        registerView(PhaseAnimator.self)
        registerView(Picker.self)
        registerView(ProgressView.self)
        registerView(ScrollView.self)
        registerView(ScrollViewReader.self)
        registerView(Section.self)
        registerView(SecureField.self)
        registerView(ShareLink.self)
        registerView(Slider.self)
        registerView(Spacer.self)
        registerView(Table.self)
        registerView(Tab.self)
        registerView(TabView.self)
        registerView(Text.self)
        registerView(TextEditor.self)
        registerView(TextField.self)
        registerView(Toggle.self)
        registerView(VStack.self)
        registerView(VideoPlayer.self)
        registerView(View.self)
        registerView(WebView.self)
        registerView(ZStack.self)
        // Removed deprecated NavigationView
        // Add more view registrations if needed
    }
    
    internal func registerAdditionalElementValidations() {
        registerPropertyValidation(WindowGroup.self)
        registerPropertyValidation(CommandGroup.self)
        registerPropertyValidation(CommandMenu.self)
    }
    
    // Registers a view construction type using its type name
    // Design decision: Simplifies registration by using String(describing: type.self), replacing ActionUIElement.registerView
    @inline(__always)
    func registerView(_ type: any ActionUIViewConstruction.Type) {
        viewRegistrations[String(describing: type.self)] = type
        logger.log("Registered view type: \(String(describing: type.self))", .verbose)
    }
    
    @inline(__always)
    func registerPropertyValidation(_ type: any ActionUIPropertyValidation.Type) {
        validationRegistrations[String(describing: type.self)] = type
        logger.log("Registered property validation for element type: \(String(describing: type.self))", .verbose)
    }

    // Validates properties for a given element type, returning unchanged properties if type not registered
    public func validateProperties(forElementType type: String, properties: [String: Any]) -> [String: Any] {
        if let constructionType = viewRegistrations[type] {
            let baseValidated = View.validateProperties(properties, logger)
            return constructionType.validateProperties(baseValidated, logger)
        }
        
        if let validationType = validationRegistrations[type] {
            return validationType.validateProperties(properties, logger)
        }
        
        logger.log("No registration found for type \(type), returning unchanged properties", .error)
        return properties
    }
    
    // Retrieves validated properties for an element, using cached validatedProperties if available
    func getValidatedProperties(element: any ActionUIElementBase, model: ViewModel) -> [String: Any] {
        if !model.validatedProperties.isEmpty {
            return model.validatedProperties
        }
                
        return validateProperties(forElementType: element.type, properties: element.properties)
    }
    
    // Retrieves the value type for a given view element type
    // Design decision: Returns Void if valueType is not implemented, ensuring compatibility with non-interactive views
    func getElementValueType(forElementType type: String) -> Any.Type {
        let valueType = viewRegistrations[type]?.valueType ?? Void.self
        return getNonOptionalType(valueType)
    }
    
    func getInitialValue(forElementType type: String, model: ViewModel) -> Any? {
        if let constructionType = viewRegistrations[type],
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
    
    func getInitialStates(forElementType type: String, model: ViewModel) -> [String: Any] {
        if let constructionType = viewRegistrations[type] {
            return constructionType.initialStates(model)
        }
        return [:]
    }
    
    // Builds a SwiftUI view for an element, only passing validatedProperties, leaving value and view-specific state to buildView
    func buildView(for element: any ActionUIElementBase, model: ViewModel, windowUUID: String, validatedProperties: [String: Any]) -> any SwiftUI.View {
        // Initialize shared state if not present
        // Design decision: Ensures all views have validatedProperties, with value and view-specific state handled by buildView
        if model.validatedProperties.isEmpty {
            model.validatedProperties = validatedProperties
        }
        
        if let constructionType = viewRegistrations[element.type] {
            return constructionType.buildView(element, model, windowUUID, validatedProperties, logger)
        }
        logger.log("No construction type found for element ID \(element.id) of type '\(element.type)' in window \(windowUUID), returning EmptyView", .warning)
        
        return SwiftUI.EmptyView()
    }
    
    // Applies modifiers to a view, using a ViewModel for dynamic updates
    // Design decision: Uses validatedProperties in model to support dynamic property changes (e.g., disabled) via setProperty, ensuring SwiftUI refreshes
    // Applies baseline View modifiers first, then view-specific modifiers, per the guide's modifier separation principle
    func applyViewModifiers(to view: any SwiftUI.View, properties: [String: Any], element: any ActionUIElementBase, model: ViewModel, windowUUID: String) -> AnyView {
        
        var modifiedView = view
        // First apply specialized view modifications if available (View.applyModifiers can erase specific view type)
        if let constructionType = viewRegistrations[element.type] {
            modifiedView = constructionType.applyModifiers(modifiedView, element, windowUUID, properties, logger)
        } else {
            logger.log("No modifier registration found for element ID \(element.id) of type '\(element.type)', applying base modifiers only", .warning)
        }
        
        // Apply base View modifications dynamically
        // Design decision: Delegates baseline modifiers (e.g., padding, disabled, hidden) to View.applyModifiers to centralize shared logic
        modifiedView = View.applyModifiers(modifiedView, element, windowUUID, properties, logger)

        return AnyView(modifiedView)
    }
}
