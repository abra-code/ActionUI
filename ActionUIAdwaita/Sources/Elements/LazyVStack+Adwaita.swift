// Sources/Elements/LazyVStack+Adwaita.swift
/*
 LazyVStack on GTK: laid out as a VStack. Its children are all made at once, not as they scroll
 into view.
*/

import CAdwaita

extension LazyVStack: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        StackLayout.makeStack(axis: .vertical)
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        let props = Props(node.properties)
        StackLayout.configure(widget, spacing: props.spacing, alignment: stackAlignment(props.alignment))
        syncContainerContent(node, widget)
    }

    static func stackAlignment(_ alignment: Props.Alignment) -> StackSolver.Alignment {
        switch alignment {
        case .leading: return .start
        case .center: return .center
        case .trailing: return .end
        }
    }
}
