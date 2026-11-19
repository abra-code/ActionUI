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
        // resource of the app: in the host's resource folder (ActionUIResourceFolder), then
        // bundled with the program.
        let source = ActionUIDocumentLoader.source(
            for: value,
            bundleURL: resourceURL,
            logger: logger
        )
        switch source {
        case .failure(let error):
            return SwiftUI.Text(error.message)
        // Each kind behind LoadableNestingGuard (Common/FileLoadableView.swift): a document that
        // loads itself is refused at the repeat, and nesting stops at a fixed depth.
        case .success(.remote(let url)):
            return LoadableNestingGuard(source: url.absoluteString, logger: logger) {
                RemoteLoadableView(url: url, windowUUID: windowUUID, isContentView: isContentView, parentID: element.id, viewDidLoadActionID: viewDidLoadActionID, logger: logger)
            }
        case .success(.file(let fileURL)):
            return LoadableNestingGuard(source: fileURL.resolvingSymlinksInPath().standardizedFileURL.absoluteString, logger: logger) {
                FileLoadableView(fileURL: fileURL, windowUUID: windowUUID, isContentView: isContentView, parentID: element.id, viewDidLoadActionID: viewDidLoadActionID, logger: logger)
            }
        }
    }

    /// A resource of the app by name and extension: in the host's resource folder
    /// (ActionUIResourceFolder), then in the main bundle.
    nonisolated static func resourceURL(_ name: String, _ ext: String) -> URL? {
        ActionUIResourceFolder.file("\(name).\(ext)").map { URL(fileURLWithPath: $0) }
            ?? Bundle.main.url(forResource: name, withExtension: ext)
    }
}
