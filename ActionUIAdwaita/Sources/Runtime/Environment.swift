// Sources/Runtime/Environment.swift
/*
 The base modifiers SwiftUI passes down to descendants through its environment, resolved for one
 node from its own properties and its ancestors', the nearest setting winning:
 multilineTextAlignment, textSelection, buttonStyle and labelsHidden; and whether it is inside a
 Form, which a Form sets for its descendants (ActionUIAdwaitaRenderer.environment), as SwiftUI's
 Form passes its style down: its controls show their titles in its label column.

 Each node computes its environment once per sync, from its parent's and its own properties
 (parents sync first), and keeps it; renderers read the kept value. When a sync changes a node's
 environment, its children are marked dirty and recompute theirs, so a change reaches the
 descendants that inherit it, and an ancestor's other property changes (its padding, its value)
 re-sync no descendant.
*/

@MainActor
struct Environment: Equatable {
    /// How the lines of multi-line text align (SwiftUI's default: leading).
    var multilineTextAlignment = BaseModifiers.TextAlignment.leading
    /// Whether text can be selected (SwiftUI's default: no).
    var textSelectable = false
    /// nil: the platform's default style (never automatic).
    var buttonStyle: BaseModifiers.ButtonStyleName?
    /// Controls show no title of their own (SwiftUI's labelsHidden).
    var labelsHidden = false
    /// Inside a Form: controls show their titles for its label column, also an empty one.
    var inForm = false

    /// This environment with an element's own settings applied over it: the nearest setting
    /// wins; automatic sets no button style, so one from further up stays (as on Apple);
    /// labelsHidden from any ancestor stays.
    func applying(_ modifiers: BaseModifiers) -> Environment {
        var environment = self
        if let alignment = modifiers.multilineTextAlignment {
            environment.multilineTextAlignment = alignment
        }
        switch modifiers.textSelection {
        case .enabled: environment.textSelectable = true
        case .disabled: environment.textSelectable = false
        case nil: break
        }
        if let style = modifiers.buttonStyle, style != .automatic {
            environment.buttonStyle = style
        }
        if modifiers.labelsHidden {
            environment.labelsHidden = true
        }
        return environment
    }
}
