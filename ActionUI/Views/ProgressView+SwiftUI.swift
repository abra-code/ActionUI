// SwiftUI rendering of ProgressView; its portable part is in Core/Elements/ProgressView.swift.

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension ProgressView: ActionUISwiftUIRenderer {
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let initialValue = Self.initialValue(model) as? Double
        let props = Props(properties)
        let title: String? = props.title
        let actionID: String? = props.actionID

        // The runtime states["progress"] override wins over the initial JSON value.
        let currentValue: Double? = model.states.double(forKey: "progress") ?? initialValue

        // total defaults to 1.0 when a value is present (matching the documented
        // contract and the Android/Web ports); a total of the wrong type reads as
        // nil. With no value at all
        // the progress is indeterminate, so total stays nil.
        let total: Double? = props.total ?? (currentValue != nil ? 1.0 : nil)

        let progressView: any SwiftUI.View
        if let value = currentValue, let total = total, value <= total {
            progressView = title != nil ?
            SwiftUI.ProgressView(title!, value: value, total: total) :
            SwiftUI.ProgressView(value: value, total: total)
        } else {
            progressView = title != nil ?
            SwiftUI.ProgressView(title!) :
            SwiftUI.ProgressView()
        }
        
        return progressView
            .onTapGesture {
                if let actionID = actionID {
                    ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                }
            }
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
        var modifiedView = view
        let props = Props(properties)
        switch props.style {
        case .linear:
            // The only way to ask for an indeterminate LINEAR bar. SwiftUI has
            // one - an indeterminate ProgressView styled .linear animates as a
            // bar - but with no style applied macOS resolves an indeterminate
            // ProgressView to the circular spinner, so a caller that wants a bar
            // of a known width for a phase it cannot measure had no way to say
            // so.
            modifiedView = modifiedView.progressViewStyle(.linear)
        case .circular:
            modifiedView = modifiedView.progressViewStyle(.circular)
        case .automatic, nil:
            // "automatic", or nothing asked for: the platform default, which is
            // what this element has always done.
#if canImport(UIKit)
            // Indeterminate (the circular spinner on iOS) when no value is supplied;
            // a missing total no longer implies indeterminate — it defaults to 1.0 in
            // buildView when a value is present.
            if props.value == nil {
                modifiedView = modifiedView.progressViewStyle(.circular)
            }
#endif
            break
        }
        return modifiedView
    }
}
