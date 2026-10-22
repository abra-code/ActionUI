// Sources/Elements/Rectangle+Adwaita.swift
/*
 Rectangle on GTK: a ShapeWidget drawing the outline with the fill, else the stroke, else the foreground
 color.
*/

import CAdwaita

extension Rectangle: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        ShapeWidget.make()
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        let props = Props(node.properties)
        ShapeWidget.update(widget, outline: .rectangle, fill: props.fill, stroke: props.stroke, lineWidth: props.strokeLineWidth)
    }

    static var defaultExpansion: Expansion { .both }
}
