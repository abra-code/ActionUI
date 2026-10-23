// Sources/Elements/HStack+Adwaita.swift
/*
 HStack on GTK: a container laid out by StackLayout along the horizontal axis. Without a spacing,
 it uses SwiftUI's default: 8 between controls, none next to a Spacer. firstTextBaseline and
 lastTextBaseline line up the children's first text baselines (Baselines; GTK reports only the
 first, so lastTextBaseline differs from SwiftUI for text of more than one line).
*/

import CAdwaita

extension HStack: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        StackLayout.makeStack(axis: .horizontal)
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        let props = Props(node.properties)
        StackLayout.configure(widget, spacing: props.spacing, alignment: stackAlignment(props.alignment),
                              alignsBaselines: props.alignment == .firstTextBaseline || props.alignment == .lastTextBaseline)
        syncContainerChildren(node, widget, node.subviews("children"))
    }

    static func stackAlignment(_ alignment: Props.Alignment) -> StackSolver.Alignment {
        switch alignment {
        case .top: return .start
        case .center: return .center
        case .bottom: return .end
        // Not used: the stack lines up baselines instead (alignsBaselines).
        case .firstTextBaseline, .lastTextBaseline: return .center
        }
    }
}
