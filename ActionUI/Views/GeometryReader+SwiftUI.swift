// SwiftUI rendering of GeometryReader; its portable part is in Core/Elements/GeometryReader.swift.

import SwiftUI

extension GeometryReader: ActionUISwiftUIRenderer {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

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
        let model: ViewModel
        let alignment: SwiftUI.Alignment
        @ViewBuilder let content: Content

        var body: some SwiftUI.View {
            let _ = model.trackAllChanges()
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
