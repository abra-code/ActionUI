// Sources/Elements/Circle+Adwaita.swift
/*
 Circle on GTK: a ShapeWidget drawing the outline with the fill, else the stroke, else the foreground
 color.
*/

import CAdwaita

extension Circle: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        ShapeWidget.make()
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        let props = Props(node.properties)
        ShapeWidget.update(widget, outline: .circle, fill: props.fill, stroke: props.stroke, lineWidth: props.strokeLineWidth)
    }

    static var defaultExpansion: Expansion { .both }
}
