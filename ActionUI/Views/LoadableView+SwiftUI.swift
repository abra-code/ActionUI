// SwiftUI rendering of LoadableView; its portable part is in Core/Elements/LoadableView.swift.

import SwiftUI
import Foundation

extension LoadableView: ActionUISwiftUIRenderer {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in

        let props = Props(properties)
        let isContentView = false
        let viewDidLoadActionID = props.viewDidLoadActionID
        // Use model.value if set (heuristics to interpret), else fall back to the current properties
        guard let value = Self.initialValue(model) as? String, !value.isEmpty else {
            logger.log("No valid source for LoadableView, displaying error SwiftUI.Text", .warning)
            return SwiftUI.Text("No valid source provided")
        }

        // Where the text points (Core/Common/DocumentLoader.swift): a remote URL, a file, or a
        // resource bundled with the program.
        let source = ActionUIDocumentLoader.source(
            for: value,
            bundleURL: { name, ext in Bundle.main.url(forResource: name, withExtension: ext) },
            logger: logger
        )
        switch source {
        case .failure(let error):
            return SwiftUI.Text(error.message)
        case .success(.remote(let url)):
            return RemoteLoadableView(url: url, windowUUID: windowUUID, isContentView: isContentView, parentID: element.id, viewDidLoadActionID: viewDidLoadActionID, logger: logger)
        case .success(.file(let fileURL)):
            return FileLoadableView(fileURL: fileURL, windowUUID: windowUUID, isContentView: isContentView, parentID: element.id, viewDidLoadActionID: viewDidLoadActionID, logger: logger)
        }
    }
}
