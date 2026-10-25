// Sources/Elements/ProgressView+Adwaita.swift
/*
 ProgressView on GTK, in the form macOS shows (measured on macOS 27):
 - a bar (GtkProgressBar) for a known progress, or for any progress with progressViewStyle
   "linear": as wide as it is offered, the title above it. Without a progress the bar pulses, as
   SwiftUI's indeterminate linear bar moves.
 - a spinner (AdwSpinner) for an unknown progress: 32 x 32, the title under it.
 - a ring for a known progress with progressViewStyle "circular": 32 x 32, filled clockwise from
   the top, the title under it (GTK has no circular gauge, so the ring is drawn).

 - The progress is Core's ProgressView.determinateProgress: states["progress"], else the value,
   out of total (1.0 when not given); none, or more than the total, is an unknown progress.
 - A tap runs Core's ProgressView.userTapped (actionID).
 - Assistive technologies read the bar, spinner or ring, named after the title; the title label
   itself is left out of the tree, so it is read once. The ring is a progress bar for them.
*/

import CAdwaita

nonisolated(unsafe) private var ringWidgetType: GType = 0
private let progressStateKey = AttachKey<ProgressState>("actionui-progress-state")

/// What the indicator shows, kept on it: the ring's fraction, and the bar's pulse.
@MainActor private final class ProgressState {
    var fraction = 0.0
    /// The tick callback that pulses an indeterminate bar; 0 when none.
    var pulseTick: guint = 0
    var lastPulse: gint64 = 0
}

extension ProgressView: ActionUIAdwaitaRenderer {
    enum Kind: Int {
        case bar = 0, spinner, ring
    }

    /// The side of the spinner and the ring, and the ring's line width.
    static let indicatorSide: Int32 = 32
    static let ringWidth: Float = 4
    /// The gap between the indicator and the title.
    static let titleSpacing: Int32 = 4
    /// How often an indeterminate bar pulses, in microseconds.
    static let pulseInterval: gint64 = 100_000

    static func widgetKind(_ node: RenderNode) -> Int {
        let props = Props(node.properties)
        let known = determinateProgress(node.model, props) != nil
        switch props.style {
        case .linear?: return Kind.bar.rawValue
        case .circular?: return (known ? Kind.ring : Kind.spinner).rawValue
        case .automatic?, nil: return (known ? Kind.bar : Kind.spinner).rawValue
        }
    }

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let kind = Kind(rawValue: node.widgetKind) ?? .bar
        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, titleSpacing)!
        // Left out of the accessibility tree: the indicator carries the title as its name.
        let title = newWidget(gtk_label_get_type(), accessibleRole: GTK_ACCESSIBLE_ROLE_PRESENTATION)
        let indicator: WidgetPointer
        switch kind {
        case .bar:
            indicator = gtk_progress_bar_new()!
            gtk_widget_set_hexpand(indicator, 1)
            gtk_widget_set_valign(indicator, GTK_ALIGN_CENTER)
            gtk_label_set_xalign(opaque(title), 0)
            gtk_box_append(typed(box), title)
            gtk_box_append(typed(box), indicator)
        case .spinner, .ring:
            indicator = kind == .spinner ? adw_spinner_new()! : typed(OpaquePointer(g_object_new_with_properties(ringType(), 0, nil, nil)!))
            gtk_widget_set_size_request(indicator, indicatorSide, indicatorSide)
            if kind == .ring {
                StyleSheet.shared.apply(["color: var(--accent-color);"], to: indicator, slot: "ringColor")
            }
            gtk_widget_set_halign(indicator, GTK_ALIGN_CENTER)
            gtk_box_append(typed(box), indicator)
            gtk_box_append(typed(box), title)
        }
        attach(ProgressState(), to: indicator, key: progressStateKey)
        if kind == .ring {
            // The state's fraction, 0, which update compares with: a ring at 0 has a value too.
            setAccessibleValue(indicator, min: 0, max: 1, now: 0)
        }
        let click = gtk_gesture_click_new()!
        connectUserSignal(UnsafeMutableRawPointer(click), "released", .press) { [weak node] in
            guard let node else { return }
            ProgressView.userTapped(element: node.element, windowUUID: node.windowUUID, props: Props(node.properties))
        }
        gtk_widget_add_controller(box, click)
        return box
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let title = titleLabel(widget) else { return }
        let indicator = accessibleWidget(widget)
        let props = Props(node.properties)
        let text = props.title ?? ""
        Gtk.Label(title).text = text
        // An empty title still takes its line, as in SwiftUI (measured on macOS 27).
        Gtk.Widget(title).isVisible = props.title != nil
        let size = node.environment.controlSize
        ControlSizeCSS.applyFont(node, to: widget)
        guard let state = attached(on: indicator, key: progressStateKey) else { return }
        let progress = determinateProgress(node.model, props)
        let fraction = progress.map { $0.total > 0 ? Swift.min(Swift.max($0.value / $0.total, 0), 1) : 0 } ?? 0
        switch Kind(rawValue: node.widgetKind) ?? .bar {
        case .bar:
            ControlSizeCSS.applyPart(ControlSizeCSS.progressBar(size), to: indicator, selector: "{} > trough")
            ControlSizeCSS.applyPart(ControlSizeCSS.progressBar(size), to: indicator, selector: "{} > trough > progress",
                                     slot: "controlSizeProgress")
            // Setting the fraction also ends the activity mode a pulse left, so a pulse that stops
            // sets it even when it is the fraction the bar had.
            let wasPulsing = state.pulseTick != 0
            setPulsing(indicator, state, progress == nil)
            if progress != nil, wasPulsing || gtk_progress_bar_get_fraction(OpaquePointer(indicator)) != fraction {
                gtk_progress_bar_set_fraction(OpaquePointer(indicator), fraction)
            }
        case .ring:
            setSide(indicator, ControlSizeCSS.spinnerSide(size))
            if state.fraction != fraction {
                state.fraction = fraction
                setAccessibleValue(indicator, min: 0, max: 1, now: fraction)
                gtk_widget_queue_draw(indicator)
            }
        case .spinner:
            setSide(indicator, ControlSizeCSS.spinnerSide(size))
        }
    }

    /// Sizes a spinner or ring `side` x `side` (controlSize; 32 at regular, macOS's).
    private static func setSide(_ indicator: WidgetPointer, _ side: Int32) {
        var width: Int32 = 0
        var height: Int32 = 0
        gtk_widget_get_size_request(indicator, &width, &height)
        if width != side || height != side {
            gtk_widget_set_size_request(indicator, side, side)
        }
    }

    /// The bar, spinner or ring, which assistive technologies read (the box only holds it and the
    /// title).
    static func accessibleWidget(_ widget: WidgetPointer) -> WidgetPointer {
        let first = Gtk.Widget(widget).firstChild?.pointer
        let last = Gtk.Widget(widget).lastChild?.pointer
        if let first, g_type_check_instance_is_a(UnsafeMutablePointer<GTypeInstance>(OpaquePointer(first)), gtk_label_get_type()) != 0 {
            return last ?? widget
        }
        return first ?? widget
    }

    /// Named after its title.
    static func defaultAccessibleLabel(_ node: RenderNode) -> String? {
        Props(node.properties).title
    }

    /// The title label: the first child above a bar, the last under a spinner or ring.
    private static func titleLabel(_ widget: WidgetPointer) -> WidgetPointer? {
        let indicator = accessibleWidget(widget)
        return Gtk.Widget(widget).firstChild?.pointer == indicator ? Gtk.Widget(widget).lastChild?.pointer : Gtk.Widget(widget).firstChild?.pointer
    }

    /// Starts or stops the bar's pulse, a tick of the frame clock (which runs only while the bar is
    /// shown).
    private static func setPulsing(_ bar: WidgetPointer, _ state: ProgressState, _ pulsing: Bool) {
        if pulsing, state.pulseTick == 0 {
            state.pulseTick = gtk_widget_add_tick_callback(bar, pulseTick, nil, nil)
        } else if !pulsing, state.pulseTick != 0 {
            gtk_widget_remove_tick_callback(bar, state.pulseTick)
            state.pulseTick = 0
        }
    }

    private static func drawRing(_ ring: WidgetPointer, _ snapshot: OpaquePointer) {
        let fraction = attached(on: ring, key: progressStateKey)?.fraction ?? 0
        // The line keeps its proportion to the side, which controlSize changes.
        let side = Float(Swift.min(gtk_widget_get_width(ring), gtk_widget_get_height(ring)))
        let lineWidth = ringWidth * Swift.min(side, Float(indicatorSide)) / Float(indicatorSide)
        // Clockwise from the top, the whole circle.
        RingDrawing.draw(ring, snapshot, lineWidth: lineWidth, start: -Float.pi / 2, sweep: 2 * Float.pi, fraction: fraction, marker: false)
    }

    /// A GtkWidget subclass that draws the ring in the accent color, 32 x 32, a progress bar for
    /// assistive technologies.
    private static func ringType() -> GType {
        if ringWidgetType != 0 { return ringWidgetType }
        var info = GTypeInfo()
        info.class_size = guint16(MemoryLayout<GtkWidgetClass>.size)
        info.instance_size = guint16(MemoryLayout<GtkWidget>.size)
        info.class_init = { klass, _ in
            guard let klass else { return }
            let widgetClass = klass.assumingMemoryBound(to: GtkWidgetClass.self)
            widgetClass.pointee.snapshot = { widget, snapshot in
                guard let widget, let snapshot else { return }
                MainActor.assumeIsolated { ProgressView.drawRing(widget, snapshot) }
            }
            gtk_widget_class_set_css_name(widgetClass, "actionui-progress-ring")
            gtk_widget_class_set_accessible_role(widgetClass, GTK_ACCESSIBLE_ROLE_PROGRESS_BAR)
        }
        ringWidgetType = g_type_register_static(gtk_widget_get_type(), "ActionUIProgressRing", &info, GTypeFlags(0))
        return ringWidgetType
    }
}

/// Pulses an indeterminate bar every pulseInterval, from its frame clock.
private let pulseTick: GtkTickCallback = { widget, clock, _ in
    guard let widget, let clock else { return 0 }
    let now = gdk_frame_clock_get_frame_time(clock)
    // A pointer is not Sendable; its address is. GTK ticks on the main thread.
    let address = UInt(bitPattern: widget)
    return MainActor.assumeIsolated {
        let widget = UnsafeMutablePointer<GtkWidget>(bitPattern: address)!
        guard let state = attached(on: widget, key: progressStateKey) else { return 0 }
        if now - state.lastPulse >= ProgressView.pulseInterval {
            state.lastPulse = now
            gtk_progress_bar_pulse(OpaquePointer(widget))
        }
        return 1
    }
}
