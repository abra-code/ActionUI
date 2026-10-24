// Sources/Elements/ScrollViewReader+Adwaita.swift
/*
 ScrollViewReader on GTK, as on Apple: the reader scrolls the ScrollViews inside it so the element
 whose id is `scrollTo` shows at `anchor` (top, center or bottom; centered horizontally, as
 SwiftUI's UnitPoint.top and .bottom are), when it first shows and again, animated, after every
 write to the reader (setElementProperty, setElementValue, setElementState: its view model's
 mutationToken), so writing the same id again brings the element back after the user scrolled
 away; shown again (a tab or a page returning), it scrolls back without animation, as SwiftUI's
 onAppear does. Each ScrollView between the element and the reader scrolls, the innermost first.

 The reader's widget holds its content as a one-child ZStack does. A request waits for the next
 layout of the ScrollViews around the element (the same write may also have moved or resized it,
 and GTK lays that out only after the main loop runs what the write scheduled): after a sync the
 reader asks them for one, and each ScrollLayout allocation, the first one too, lets a waiting
 reader scroll on the next turn of the main loop (layoutChanged). An outer ScrollView scrolls to
 where the element is once the inner ones have scrolled. A scroll after a write is an
 AdwTimedAnimation of the adjustment's value, which jumps to the end when the widget is not on
 screen or animations are off; a new scroll stops the running ones where they are.
*/

import CAdwaita

/// A reader's last write it acted on, and the scroll waiting for the element's layout.
@MainActor
final class ScrollReaderState {
    struct Request {
        let target: Int
        let anchor: ScrollViewReader.Props.Anchor
        let animated: Bool
    }

    weak var node: RenderNode?
    /// The reader's mutationToken when it last asked to scroll; nil before its first sync.
    var handledWrite: Int?
    var pending: Request?
    /// The scroll animations started last, stopped when a new scroll starts (a playing AdwAnimation
    /// holds a reference to itself, so releasing it does not stop it).
    var animations: [Animation] = []

    /// One AdwAnimation's reference.
    final class Animation {
        let owned: OwnedObject
        init(_ owned: consuming OwnedObject) { self.owned = owned }
    }

    init(node: RenderNode) {
        self.node = node
    }
}

let scrollReaderStateKey = AttachKey<ScrollReaderState>("actionui-scroll-reader")

extension ScrollViewReader: ActionUIAdwaitaRenderer {
    /// How long a scroll after a write takes, about as long as SwiftUI's default animation.
    static let scrollDuration: guint = 350

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let widget = ZStackLayout.makeStack()
        let state = ScrollReaderState(node: node)
        attach(state, to: widget, key: scrollReaderStateKey)
        // Shown again (a tab or a page returning): back to scrollTo without animation, as SwiftUI's
        // onAppear does. The first showing finds the first sync's request already waiting.
        connectSignal(widget, "map", .instanceOnly) { [weak state] in
            guard let state else { return }
            shownAgain(state)
        }
        return widget
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let state = attached(on: widget, key: scrollReaderStateKey) else { return }
        let content = node.effectiveElement.subviews?["content"] as? any ActionUIElementBase
        syncContainerChildren(node, widget, content.map { [$0] } ?? [])

        let props = Props(node.properties)
        let write = node.model.mutationToken
        guard write != state.handledWrite else { return }
        let animated = state.handledWrite != nil
        state.handledWrite = write
        guard let target = props.scrollTo else {
            state.pending = nil
            return
        }
        state.pending = ScrollReaderState.Request(target: target, anchor: props.anchor, animated: animated)
        // After this sync (the element's node may be made during it).
        runAfter(milliseconds: 0) { [weak state] in
            guard let state else { return }
            requestLayout(state)
        }
    }

    /// The reader was mapped: scroll to scrollTo again, without animation, unless a request waits.
    static func shownAgain(_ state: ScrollReaderState) {
        guard state.pending == nil, let node = state.node else { return }
        let props = Props(node.properties)
        guard let target = props.scrollTo else { return }
        state.pending = ScrollReaderState.Request(target: target, anchor: props.anchor, animated: false)
        requestLayout(state)
    }

    /// Asks the ScrollViews between the waiting request's element and the reader for a new layout,
    /// after which layoutChanged scrolls. A request for an element the reader does not hold, or one
    /// in no ScrollView, is dropped.
    static func requestLayout(_ state: ScrollReaderState) {
        guard let request = state.pending, let node = state.node, node.isAttached else { return }
        guard let target = descendant(request.target, of: node)?.outerWidget else {
            state.pending = nil
            return
        }
        let reader: WidgetPointer = node.widget
        var inScrollView = false
        var current = Gtk.Widget(target).parent
        while let widget = current, widget.pointer != reader {
            if widget.isA(gtk_scrolled_window_get_type()),
               let configuration = attached(on: widget.pointer, key: scrollConfigurationKey) {
                gtk_widget_queue_allocate(configuration.content)
                inScrollView = true
            }
            current = widget.parent
        }
        if !inScrollView {
            state.pending = nil
        }
    }

    /// Called after a ScrollView's content is laid out: a reader around it with a request waiting
    /// for that layout scrolls on the next turn of the main loop (not inside the allocation).
    static func layoutChanged(_ content: WidgetPointer) {
        var current = Gtk.Widget(content).parent
        while let widget = current {
            if let state = attached(on: widget.pointer, key: scrollReaderStateKey), state.pending != nil {
                runAfter(milliseconds: 0) { [weak state] in
                    guard let state else { return }
                    applyPending(state)
                }
            }
            current = widget.parent
        }
    }

    /// Scrolls to the waiting request's element, unless it has not been laid out yet. A request for
    /// an element the reader does not hold, or one in no ScrollView, is dropped.
    static func applyPending(_ state: ScrollReaderState) {
        guard let request = state.pending, let node = state.node, node.isAttached else { return }
        guard let target = descendant(request.target, of: node)?.outerWidget else {
            state.pending = nil
            return
        }
        let reader: WidgetPointer = node.widget
        // The ScrollViews between the element and the reader, innermost first; all laid out.
        var scrollers: [(scroller: WidgetPointer, content: WidgetPointer, bounds: graphene_rect_t)] = []
        var current = Gtk.Widget(target).parent
        while let widget = current, widget.pointer != reader {
            if widget.isA(gtk_scrolled_window_get_type()),
               let configuration = attached(on: widget.pointer, key: scrollConfigurationKey) {
                var bounds = graphene_rect_t()
                let vertical = gtk_scrolled_window_get_vadjustment(OpaquePointer(widget.pointer))
                guard gtk_widget_compute_bounds(target, configuration.content, &bounds) != 0,
                      let vertical, gtk_adjustment_get_page_size(vertical) > 0 else { return }
                scrollers.append((widget.pointer, configuration.content, bounds))
            }
            current = widget.parent
        }
        state.pending = nil
        for animation in state.animations where adw_animation_get_state(animation.owned.typed()) == ADW_ANIMATION_PLAYING {
            adw_animation_pause(animation.owned.typed())
        }
        state.animations = []
        let anchor: Double
        switch request.anchor {
        case .top: anchor = 0
        case .center: anchor = 0.5
        case .bottom: anchor = 1
        }
        // How far the inner ScrollViews scrolled moves the element in the outer ones' content.
        var moved = (x: 0.0, y: 0.0)
        for (scroller, _, bounds) in scrollers {
            let window = OpaquePointer(scroller)
            if let horizontal = gtk_scrolled_window_get_hadjustment(window) {
                moved.x += scroll(horizontal, start: Double(bounds.origin.x) - moved.x, length: Double(bounds.size.width),
                                  anchor: 0.5, animated: request.animated, widget: scroller, state: state)
            }
            if let vertical = gtk_scrolled_window_get_vadjustment(window) {
                moved.y += scroll(vertical, start: Double(bounds.origin.y) - moved.y, length: Double(bounds.size.height),
                                  anchor: anchor, animated: request.animated, widget: scroller, state: state)
            }
        }
    }

    /// Moves `adjustment` so the span from `start`, `length` long, has its `anchor` point (0 start,
    /// 1 end) at the same point of the visible page, within the adjustment's range. Returns how far
    /// it moves.
    private static func scroll(_ adjustment: UnsafeMutablePointer<GtkAdjustment>, start: Double, length: Double, anchor: Double,
                               animated: Bool, widget: WidgetPointer, state: ScrollReaderState) -> Double {
        let page = gtk_adjustment_get_page_size(adjustment)
        let lower = gtk_adjustment_get_lower(adjustment)
        let upper = max(gtk_adjustment_get_upper(adjustment) - page, lower)
        let value = min(max(start + length * anchor - page * anchor, lower), upper)
        let current = gtk_adjustment_get_value(adjustment)
        guard abs(value - current) >= 0.5 else { return 0 }
        guard animated else {
            gtk_adjustment_set_value(adjustment, value)
            return value - current
        }
        // The animation takes the target's reference.
        let target = adw_property_animation_target_new(typed(adjustment), "value")
        let animation = OwnedObject(adopting: adw_timed_animation_new(widget, current, value, scrollDuration, target)!)
        adw_timed_animation_set_easing(animation.opaquePointer, ADW_EASE_OUT_CUBIC)
        adw_animation_play(animation.typed())
        state.animations.append(ScrollReaderState.Animation(animation))
        return value - current
    }

    /// The node of the element with `id` among `node`'s descendants.
    private static func descendant(_ id: Int, of node: RenderNode) -> RenderNode? {
        for child in node.childNodes.values {
            if child.element.id == id { return child }
            if let found = descendant(id, of: child) { return found }
        }
        return nil
    }
}
