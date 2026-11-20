// Sources/Elements/Form+WinUI.swift
/*
 Form on WinUI: laid out as macOS lays out a Form (its columns style; measured on macOS 27 for the
 Linux renderer): a column of its rows, 8 points apart and aligned to its leading edge, as large as its
 rows unless one of them fills, and centered in its parent like a VStack. A Section's rows are laid out
 as the Form's own (Section+WinUI).
 The titles of its LabeledContent, Picker, DatePicker, Stepper, switch Toggle, TextField and SecureField
 rows (a Section's too) end at a label column as wide as the widest title, and every row's content starts
 8 points after it: a titled row is moved so its title ends at the column (its own title, gap and
 control kept: a frame on it holds all three, as on macOS), and a row without a title (a Text, a Button,
 a checkbox Toggle, a Section's header) starts 8 after it (FormColumn, as the Linux renderer's
 offsets). With no titled row there is no column and the rows start at the Form's leading edge; an empty title makes a column of
 0; a Picker's, DatePicker's, Stepper's, switch's, TextField's or SecureField's title labelsHidden hides
 makes its row one without a title (FormColumn, as on Linux; LabeledContent has no labelsHidden yet). A row's title change, and a
 Section's rows changing, lay the Form out again, as neither need change the size of what holds them.

 Not yet: 5 points instead of 8 above a row with text below a row without (measured on macOS); a row's
 padding or frame moving its title, and a stack row's titles (Linux takes them into the column).
*/

extension Form: ActionUIWinUIRenderer {
    /// The space between two rows, measured on macOS 27.
    static let rowSpacing = 8.0

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let view = try StackViews.make(node, axis: .vertical)
        if let stack = StackViews.stack(of: node) {
            // The label column is worked out before each measure of the rows.
            let measureRows = stack.panel.measure
            stack.panel.measure = { [weak node, unowned stack] available in
                if let node {
                    FormColumn.apply(node, stack)
                }
                return measureRows(available)
            }
        }
        return view
    }

    static func expansion(_ node: RenderNode) -> Expansion { StackViews.childrenExpansion(node) }

    static func compression(_ node: RenderNode) -> Expansion { StackViews.childrenCompression(node) }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let stack = StackViews.stack(of: node) else { return }
        StackViews.configure(stack, spacing: rowSpacing, alignment: .start)
        syncStackContent(node, stack)
    }
}

/// A row layout whose title a Form lines up in its label column: the title first, at the row's leading
/// edge.
@MainActor protocol FormLabeledLayout: AnyObject {
    /// The title's width as the row shows it; nil when it shows none (labelsHidden).
    func formTitleWidth() -> Double?
    /// Asks the Form to lay its rows out again, after the title changed.
    var formChanged: (() -> Void)? { get set }
}

/// A Form's label column (as the Linux renderer's FormLayout): the widest title among its rows, its
/// Sections' rows included, sets the column; a titled row is set in by the column less its title, so the
/// title ends at the column, and a row without a title by the column and 8 (its stack's leading inset).
@MainActor enum FormColumn {
    private struct Row {
        let view: WinUIObject
        let stack: StackLayout
        let labeled: FormLabeledLayout?
    }

    static func apply(_ form: RenderNode, _ stack: StackLayout) {
        var rows: [Row] = []
        collect(form, stack, into: &rows)
        let widths = rows.map { $0.labeled?.formTitleWidth() }
        // In whole points, as the insets are: a titled row's content then lands within half a point of
        // column + 8, the same edge as the rows without a title.
        let column = widths.compactMap { $0 }.max().map { $0.rounded(.up) }
        var stacks: [ObjectIdentifier: StackLayout] = [ObjectIdentifier(stack): stack]
        var insets: [ObjectIdentifier: [ObjectIdentifier: Int]] = [:]
        for (row, width) in zip(rows, widths) {
            let key = ObjectIdentifier(row.stack)
            stacks[key] = row.stack
            row.labeled?.formChanged = { [weak panel = stack.panel] in panel?.invalidateLayout() }
            let inset = column.map { column in
                width.map { Int((column - $0).rounded()) } ?? Int((column + StackLayout.defaultSpacing).rounded(.up))
            } ?? 0
            insets[key, default: [:]][ObjectIdentifier(row.view)] = inset
        }
        for (key, rowStack) in stacks {
            // The Form's own stack is measuring now, with them.
            rowStack.setLeadingInsets(insets[key] ?? [:], invalidate: rowStack !== stack)
        }
    }

    /// The rows of `node` (a Form or a Section) in `stack`: a Section's header and rows are the Form's.
    private static func collect(_ node: RenderNode, _ stack: StackLayout, into rows: inout [Row]) {
        // A Section's rows: its children, or its template instances.
        let children = node.orderedChildren + ((node.state as? SectionState)?.stack.templateRows.nodes ?? [])
        for child in children {
            guard let view = child.outerView else { continue }
            if let section = child.state as? SectionState {
                if !(section.shownHeader ?? "").isEmpty {
                    rows.append(Row(view: section.header, stack: section.stack, labeled: nil))
                }
                collect(child, section.stack, into: &rows)
            } else {
                rows.append(Row(view: view, stack: stack, labeled: labeledLayout(child)))
            }
        }
    }

    /// The layout of a row that shows a title, nil for any other.
    private static func labeledLayout(_ node: RenderNode) -> FormLabeledLayout? {
        switch node.state {
        case let state as PickerState: return state.layout
        case let state as DatePickerState: return state.layout
        case let state as StepperState: return state.layout
        case let layout as LabeledContentLayout: return layout
        case let state as ToggleState: return state.layout
        case let state as TextFieldState: return state.layout
        default: return nil
        }
    }

    /// Whether `node` is a row of a Form (of the Form or of its Sections): a switch, a TextField and a
    /// SecureField then show their title in its label column. Read when the element is made.
    static func isRow(_ node: RenderNode) -> Bool {
        var parent = node.parent
        while let current = parent, current.element.type == "Section" {
            parent = current.parent
        }
        return parent?.element.type == "Form"
    }
}
