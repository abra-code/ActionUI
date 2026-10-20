// Sources/Views/GeometryReader.swift
/*
 Sample JSON for GeometryReader:
 {
   "type": "GeometryReader",
   "id": 1,              // Required: Non-zero positive integer (size is reported via states on this model)
   "content": {          // Required: Single child view. Note: Declared as a top-level key in JSON but stored in subviews["content"] by ActionUIElement.init(from:).
     "type": "Text", "properties": { "text": "Content" }
   },
   "properties": {
     "alignment": "center"  // Optional: Content alignment — "topLeading" (SwiftUI default), "center", "top",
                             //   "bottom", "leading", "trailing", "topTrailing", "bottomLeading", "bottomTrailing".
                             //   GeometryReader's SwiftUI default is topLeading; set "center" to center content.
   }
 }

 // Behavior: GeometryReader is a greedy container — it expands to fill all available space
 // offered by its parent, regardless of its content's size. This makes it useful for:
 //   - Forcing a view to fill available space (e.g., full-screen overlays)
 //   - Reading the container's size for responsive layout decisions
 // SwiftUI default alignment is .topLeading (not .center like most containers).
 //
 // The container's size is exposed via observable state so clients can react to layout:
 //   states["size"]  [Double, Double]   Container width and height as [width, height].
 //                                      Updated when the container's size changes.
 //                                      Read via getElementState(windowUUID:, viewID:, key: "size").
 //
 // Platform behavior: Identical on iOS and macOS — always greedy, always topLeading default.
 // As a subview of HStack/VStack, GeometryReader consumes all remaining flexible space,
 // pushing siblings to their minimum size. Use with care in stacks.
 //
 // Note: These properties are specific to GeometryReader. Baseline View properties (padding, hidden,
 // foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional
 // View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to:
 // baseView, properties: element.properties).
*/

import SwiftUI

extension GeometryReader {
    /// GeometryReader's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        enum Alignment: String, Sendable, CaseIterable {
            case topLeading, top, topTrailing, leading, center, trailing, bottomLeading, bottom, bottomTrailing
        }

        /// A name that is not one of the nine, or no string, is topLeading (GeometryReader's own default).
        var alignment = Alignment.topLeading

        init(_ properties: [String: Any]) {
            alignment = (properties["alignment"] as? String).flatMap(Alignment.init(rawValue:)) ?? .topLeading
        }
    }
}

struct GeometryReader: ActionUIViewConstruction {
    static var valueType: Any.Type = Void.self
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var initialStates: (ViewModel) -> [String: Any] = { model in
        var states = model.states
        if states["size"] == nil {
            states["size"] = [0.0, 0.0] as [Double]
        }
        return states
    }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let content = element.subviews?["content"] as? any ActionUIElementBase ?? ActionUIElement(id: ActionUIElement.generateNegativeID(), type: "EmptyView", properties: [:], subviews: nil)
        let props = Props(properties)
        let alignment = resolveAlignment(props.alignment)

        return GeometryReaderContainer(model: model, alignment: alignment) {
            if let windowModel = ActionUIModel.shared.windowModels[windowUUID],
               let childModel = windowModel.viewModels[content.id] {
                ActionUIView(element: content, model: childModel, windowUUID: windowUUID)
            } else {
                SwiftUI.EmptyView()
            }
        }
    }

    /// Resolves an alignment string to SwiftUI.Alignment.
    /// Defaults to .topLeading (GeometryReader's native default).
    private static func resolveAlignment(_ alignment: Props.Alignment) -> SwiftUI.Alignment {
        switch alignment {
        case .center: return .center
        case .top: return .top
        case .bottom: return .bottom
        case .leading: return .leading
        case .trailing: return .trailing
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        case .topLeading: return .topLeading
        }
    }

    /// Wrapper view that uses SwiftUI.GeometryReader and reports size changes
    /// back to the ViewModel's states["size"].
    private struct GeometryReaderContainer<Content: SwiftUI.View>: SwiftUI.View {
        @ObservedObject var model: ViewModel
        let alignment: SwiftUI.Alignment
        @ViewBuilder let content: Content

        var body: some SwiftUI.View {
            SwiftUI.GeometryReader { proxy in
                content
                    .frame(
                        maxWidth: alignment == .topLeading ? nil : .infinity,
                        maxHeight: alignment == .topLeading ? nil : .infinity,
                        alignment: alignment
                    )
                    .onChange(of: proxy.size) { _, newSize in
                        let sizeArray = [Double(newSize.width), Double(newSize.height)]
                        if model.states["size"] as? [Double] != sizeArray {
                            DispatchQueue.main.async {
                                model.states["size"] = sizeArray
                            }
                        }
                    }
                    .onAppear {
                        let sizeArray = [Double(proxy.size.width), Double(proxy.size.height)]
                        if model.states["size"] as? [Double] != sizeArray {
                            DispatchQueue.main.async {
                                model.states["size"] = sizeArray
                            }
                        }
                    }
            }
        }
    }
}
