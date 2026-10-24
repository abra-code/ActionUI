// Sources/Elements/ZStack+Adwaita.swift
/*
 ZStack on GTK: a container laid out by ZStackLayout, its children (or one template instance
 per content row, as VStack's) layered in order.
*/

import CAdwaita

extension ZStack: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        ZStackLayout.makeStack()
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        let props = Props(node.properties)
        let alignment = alignments(props.alignment)
        ZStackLayout.configure(widget, horizontal: alignment.horizontal, vertical: alignment.vertical)
        syncContainerContent(node, widget)
    }

    static func alignments(_ alignment: Props.Alignment) -> (horizontal: StackSolver.Alignment, vertical: StackSolver.Alignment) {
        switch alignment {
        case .topLeading: return (.start, .start)
        case .top: return (.center, .start)
        case .topTrailing: return (.end, .start)
        case .leading: return (.start, .center)
        case .center: return (.center, .center)
        case .trailing: return (.end, .center)
        case .bottomLeading: return (.start, .end)
        case .bottom: return (.center, .end)
        case .bottomTrailing: return (.end, .end)
        }
    }
}
