// Helpers/TemplateHelper+SwiftUI.swift
/*
 The SwiftUI side of TemplateHelper: building one template instance as a SwiftUI view through
 the registry. The column substitution, the row Booleans and the row write-back are in
 Core/Helpers/TemplateHelper.swift.
*/

import SwiftUI

extension TemplateHelper {
    // MARK: - Template View Building

    /// Build a SwiftUI view from a template element and a single data row using
    /// the full ActionUI registry pipeline.
    ///
    /// A throw-away ViewModel is created with TemplateContext set, enabling:
    /// - Button to dispatch actions with parentID/rowIndex
    /// - Container views to render children via TemplateHelper
    /// - All registered view types to work with full property and modifier support
    ///
    /// - Parameters:
    ///   - template:    The template element (from subviews["template"] or a child thereof)
    ///   - row:         Column strings for this row
    ///   - rowIndex:    0-based row index; used as viewPartID in action dispatch
    ///   - parentID:    The owning container's element id; used as viewID in action dispatch
    ///   - windowUUID:  Window identifier
    ///   - logger:      Logger instance
    /// - Returns: A rendered SwiftUI view wrapped in AnyView
    static func buildTemplateView(
        template: any ActionUIElementBase,
        row: [String],
        rowIndex: Int,
        parentID: Int,
        windowUUID: String,
        logger: any ActionUILogger
    ) -> AnyView {
        let substitutedProps = instanceProperties(of: template, row: row, logger: logger)

        let vm = ViewModel()
        vm.templateContext = TemplateContext(parentID: parentID, rowIndex: rowIndex, row: row)
        vm.seedProperties(substitutedProps)

        // The reads of the throw-away model are not tracked: the container builds a new one on
        // every render, and a tracked read would make the container render again when a control in
        // the row writes it (a TextField or Slider setting its value), which builds the row from
        // its data again and resets the control.
        let registry = ActionUIRegistry.shared
        return UntrackedReads.perform {
            let view = registry.buildView(
                for: template, model: vm, windowUUID: windowUUID, properties: substitutedProps
            )
            return registry.applyViewModifiers(
                to: view, properties: substitutedProps, element: template, model: vm, windowUUID: windowUUID
            )
        }
    }
}
