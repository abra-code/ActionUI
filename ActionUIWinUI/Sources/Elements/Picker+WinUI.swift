// Sources/Elements/Picker+WinUI.swift
/*
 Picker on WinUI: the title beside the choice, as macOS shows it and as the Linux renderer does, in
 Windows' own controls:
 - menu, wheel and no style: a ComboBox (macOS shows a wheel as its menu);
 - segmented: a SelectorBar, the Windows App SDK's selector of side-by-side items;
 - radioGroup: a RadioButtons group, a column of radio buttons with the title beside the first; with
   horizontalRadioGroupLayout a row of them.
 The title, 8 points, then the control; an empty title keeps its gap (as for every control on macOS,
 measured on macOS 27); labelsHidden hides the title and its gap.

 - The options are the items, in order (sections and dividers are not shown yet).
 - The selected item is the one whose tag is the value, else the first option (Picker.initialValue); a
   value that is no option's tag selects none.
 - Choosing an item runs Core's Picker.userSelected (the value, then actionID with the tag as
   context). The controls also report the renderer's own selection, which the handler ignores (it
   is the index the renderer last selected; userSelected would not, for a first option shown in
   place of a value that is no String).
 - The style is read when the element is made (a later change of style keeps the first control).

 Not yet: sections and dividers (a menu's headers and lines); the title as the control's accessible
 name when labelsHidden hides it; the dropdown as wide as its widest item (a ComboBox takes its
 selected item's width).
*/

import CWinUI

/// A title beside a control, `spacing` apart: a Picker's.
@MainActor
final class TitledControlLayout: FormLabeledLayout {
    static let spacing = 8.0

    let panel: LayoutPanel
    let title: WinUIObject
    let control: WinUIObject
    /// labelsHidden: no title and no gap.
    var titleHidden = false {
        didSet {
            if titleHidden != oldValue {
                panel.invalidateLayout()
                // In a Form the column may change without this row's size.
                formChanged?()
            }
        }
    }
    /// The control's rows of equal height (a radio group's buttons in a column), for the title to sit
    /// centered on the first; 1 centers it on the whole control.
    var rows = 1 {
        didSet { if rows != oldValue { panel.invalidateLayout() } }
    }
    /// The control takes the width the row has after the title (a text field in a Form, as wide as
    /// it is offered), rather than its own.
    var controlFills = false {
        didSet { if controlFills != oldValue { panel.invalidateLayout() } }
    }
    private var shownTitle: String?
    private var measuredTitle = ActionUIWinUISize(width: 0, height: 0)
    private var measuredControl = ActionUIWinUISize(width: 0, height: 0)

    /// The title's width, nil when labelsHidden hides it.
    func formTitleWidth() -> Double? {
        titleHidden ? nil : title.measure(ActionUIWinUISize(width: .infinity, height: .infinity)).width
    }

    init(control: WinUIObject) throws(WinUIError) {
        panel = try LayoutPanel()
        guard let title = WinUIObject(adopting: actionUIWinUITextBlockCreate()) else {
            throw WinUIError.last("creating a title")
        }
        self.title = title
        self.control = control
        try panel.append(title)
        try panel.append(control)
        panel.measure = { [unowned self] available in measure(available) }
        panel.arrange = { [unowned self] finalSize in arrange(finalSize) }
    }

    func setTitle(_ text: String) {
        guard text != shownTitle else { return }
        if !actionUIWinUITextBlockSetText(title.pointer, text) {
            ActionUIModel.shared.logger.log("Picker: \(WinUIError.last("setting the title"))", .error)
            return
        }
        shownTitle = text
        panel.invalidateLayout()
        // In a Form its row keeps its size; the Form works its column out again.
        formChanged?()
    }

    /// Asks the Form this row is in to lay its rows out again (FormColumn sets it).
    var formChanged: (() -> Void)?

    private var leading: Double { titleHidden ? 0 : measuredTitle.width + Self.spacing }

    private func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        let titleSize = title.measure(ActionUIWinUISize(width: .infinity, height: .infinity))
        measuredTitle = titleHidden ? ActionUIWinUISize(width: 0, height: 0) : titleSize
        let offer = ActionUIWinUISize(width: available.width.isFinite ? max(available.width - leading, 0) : .infinity,
                                      height: available.height)
        measuredControl = control.measure(offer)
        if controlFills && offer.width.isFinite {
            measuredControl.width = max(measuredControl.width, offer.width)
        }
        return ActionUIWinUISize(width: leading + measuredControl.width, height: max(measuredTitle.height, measuredControl.height))
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        // At their own sizes, centered in a wider frame (macOS centers its pop-up button there, as the
        // Linux renderer does); in a narrower one the control gets what is left.
        // A control that fills starts after the title.
        let start = controlFills ? 0 : max((finalSize.width - leading - measuredControl.width) / 2, 0)
        let room = max(finalSize.width - leading, 0)
        let controlWidth = controlFills ? room : min(measuredControl.width, room)
        let controlY = (finalSize.height - measuredControl.height) / 2
        let firstRow = measuredControl.height / Double(max(rows, 1))
        let titleY = controlY + (firstRow - measuredTitle.height) / 2
        title.arrange(ActionUIWinUIRect(x: start, y: titleY, width: measuredTitle.width, height: measuredTitle.height))
        control.arrange(ActionUIWinUIRect(x: start + leading, y: controlY, width: controlWidth, height: measuredControl.height))
    }
}

/// A Picker's layout and what its control shows.
@MainActor final class PickerState {
    let layout: TitledControlLayout
    let kind: ActionUIWinUIChoiceKind
    /// The items' titles and tags, in the control's order.
    var titles: [String]?
    var tags: [String] = []
    /// The index the renderer last selected: a selection event reporting it is the renderer's own
    /// (which can show a tag that is not the value: the first option for a value that is no String).
    var shownIndex = -1
    var appliedAppearance: TextAppearance?

    init(layout: TitledControlLayout, kind: ActionUIWinUIChoiceKind) {
        self.layout = layout
        self.kind = kind
    }
}

extension Picker: ActionUIWinUIRenderer {
    /// The control for the element's style; read without tracking, at creation.
    static func kind(_ node: RenderNode) -> ActionUIWinUIChoiceKind {
        switch UntrackedReads.perform({ Props(node.properties).style }) {
        case .segmented: return ActionUIWinUIChoiceSegments
        case .radioGroup: return ActionUIWinUIChoiceRadio
        case .menu, .wheel, nil: return ActionUIWinUIChoiceMenu
        }
    }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let kind = kind(node)
        guard let control = WinUIObject(adopting: actionUIWinUIChoiceCreate(kind)) else {
            throw WinUIError.last("creating a Picker's control")
        }
        let layout = try TitledControlLayout(control: control)
        let state = PickerState(layout: layout, kind: kind)
        node.state = state
        WinUIEvents.connect(control, actionUIWinUIChoiceOnSelectionChanged, "a Picker's selection") { [weak node, weak state, weak control] in
            guard let node, let state, let control, node.isAttached else { return }
            let index = Int(actionUIWinUIChoiceGetSelectedIndex(control.pointer))
            guard state.tags.indices.contains(index), index != state.shownIndex else { return }
            state.shownIndex = index
            Picker.userSelected(state.tags[index], element: node.element, model: node.model,
                                windowUUID: node.windowModel.windowUUID, props: Props(node.properties))
        }
        return layout.panel.object
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? PickerState else { return }
        let layout = state.layout
        let props = Props(node.properties)
        layout.setTitle(props.title)
        layout.titleHidden = node.isLabelsHidden
        // The title keeps its color when the Picker is disabled: macOS dims only the control (measured).
        let enabled = !(node.isDisabled || node.isHidden)
        if state.appliedAppearance != node.textAppearance {
            state.appliedAppearance = node.textAppearance
            node.textAppearance.apply(to: layout.title, what: "a Picker's title")
            node.textAppearance.apply(to: layout.control, what: "a Picker")
        }
        node.applyAccessibilityHidden(to: layout.title)
        node.applyAccessibilityHidden(to: layout.control)
        // RenderNode enables the view, which is the layout's panel (no Control): the control is
        // enabled here.
        if !actionUIWinUIElementSetEnabled(layout.control.pointer, enabled) {
            ActionUIModel.shared.logger.log("Picker: \(WinUIError.last("enabling the control"))", .error)
        }
        let options = props.options
        let titles = options.map(\.title)
        state.tags = options.map(\.tag)
        if titles != state.titles {
            state.titles = titles
            let set = withCStrings(titles) { actionUIWinUIChoiceSetItems(layout.control.pointer, $0, Int32(titles.count)) }
            if !set {
                ActionUIModel.shared.logger.log("Picker: \(WinUIError.last("setting the options"))", .error)
            }
            layout.panel.invalidateLayout()
        }
        if state.kind == ActionUIWinUIChoiceRadio {
            if !actionUIWinUIChoiceSetColumns(layout.control.pointer, props.horizontalRadioGroupLayout ? Int32(max(titles.count, 1)) : 1) {
                ActionUIModel.shared.logger.log("Picker: \(WinUIError.last("laying out the radio buttons"))", .error)
            }
            // The title beside the first button: a column has a row per button.
            layout.rows = props.horizontalRadioGroupLayout ? 1 : max(titles.count, 1)
        }
        let value = Picker.initialValue(node.model) as? String
        let index = value.flatMap { state.tags.firstIndex(of: $0) } ?? -1
        // Before the call, whose event can come at once; after it, what the control shows.
        state.shownIndex = index
        if !actionUIWinUIChoiceSetSelectedIndex(layout.control.pointer, Int32(index)) {
            ActionUIModel.shared.logger.log("Picker: \(WinUIError.last("selecting an option"))", .error)
        }
        state.shownIndex = Int(actionUIWinUIChoiceGetSelectedIndex(layout.control.pointer))
    }

    /// Calls `body` with `strings` as an array of C strings, valid during the call.
    private static func withCStrings<Result>(_ strings: [String], _ body: (UnsafePointer<UnsafePointer<CChar>?>?) -> Result) -> Result {
        let copies: [UnsafeMutablePointer<CChar>] = strings.map { string in
            let utf8 = Array(string.utf8CString)
            let copy = UnsafeMutablePointer<CChar>.allocate(capacity: utf8.count)
            copy.initialize(from: utf8, count: utf8.count)
            return copy
        }
        defer { copies.forEach { $0.deallocate() } }
        let pointers: [UnsafePointer<CChar>?] = copies.map { UnsafePointer($0) }
        return pointers.withUnsafeBufferPointer { body($0.baseAddress) }
    }
}
