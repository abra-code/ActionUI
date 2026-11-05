// Sources/Runtime/BoxAnimation.swift
/*
 The `animation` and `transition` modifiers on the GTK renderer.

 When it runs, as on Apple (View.applyModifiers' .animation(_:value:)): a sync of an element that
 declares an animation animates when its trigger (BaseModifiers.Animation.trigger) differs from
 the one its box saw at the sync before. Without `value` that is every host mutation of the
 element (setElementProperty, setElementState, setElementValue); with it, a change of the watched
 property, state or value. The first sync, a sync in which the animation is new, and what the
 user's own input changes do not animate.

 What moves, with SwiftUI's curves (AnimationTiming):
 - What the box draws itself, through a libadwaita animation on the box: opacity, offset,
   rotation, scale and the shadow, from what the box shows (part of the way through an earlier
   animation too) to the new values. A spring can overshoot, as SwiftUI's does; opacity stays in
   0...1 and a shadow's blur at 0 or more.
 - Background, border and corner radius on the content group, and the foreground color on the
   element widget, through a GTK CSS transition armed on them (ModifierBox).
 - At once: hidden (whose opacity change is not animated, as hidden also stops input), a shadow
   that appears or goes, the scale anchor, fonts and tint.
 Not animated: layout. A changed frame, padding or alignment, and what moves in a stack because of
 it, which SwiftUI animates too, take their new places at once.

 The transition's insertion: an element the host inserts (insertElement, insertRow) into a node
 shown before plays its declared transition's insertion half, as SwiftUI's withAnimation around
 the insert does (WindowModel): from the transition's state to rest, with .default, the smooth
 spring. opacity starts transparent, scale from its factor (SwiftUI's 0.00001 when none) around its
 anchor, move and slide one frame's width or height off toward the edge, offset by its points;
 combined ones together, an asymmetric one's insertion half. Only the inserted element plays it, not
 what it holds, and not in a List, whose rows SwiftUI animates its own way (on macOS not at all).
 The transition's effects lie outside the element's own (BoxLayout), as SwiftUI applies .transition
 last. A host's change during it that does not animate continues with the transition's curve.
 Not done: the removal half (the element leaves at once, as on Android and Web), and leading and
 trailing are not mirrored in a right-to-left layout.

 libadwaita ends an animation at once when the box is not on screen or the desktop turns
 animations off (GtkSettings:gtk-enable-animations), and so does a GTK CSS transition.
*/

import CAdwaita

/// A shadow's color and geometry, as a box draws it.
struct ShadowValue: Equatable {
    var red: Float
    var green: Float
    var blue: Float
    var alpha: Float
    var dx: Float
    var dy: Float
    var radius: Float

    var gsk: GskShadow {
        GskShadow(color: GdkRGBA(red: red, green: green, blue: blue, alpha: alpha), dx: dx, dy: dy, radius: radius)
    }
}

/// What a box draws that an animation moves: opacity, offset, then rotation in degrees, then
/// scale (BoxLayout), and the shadow.
struct BoxVisuals: Equatable {
    var opacity = 1.0
    var hidden = false
    var offsetX = 0.0
    var offsetY = 0.0
    var rotation = 0.0
    var scaleX = 1.0
    var scaleY = 1.0
    var shadow: ShadowValue?
    /// An insertion transition's state (BoxAnimation.enter): an opacity factor, a scale, a move by
    /// a share of the frame's size and an offset in points; at rest, identity.
    var enterOpacity = 1.0
    var enterScaleX = 1.0
    var enterScaleY = 1.0
    var enterMoveX = 0.0
    var enterMoveY = 0.0
    var enterOffsetX = 0.0
    var enterOffsetY = 0.0

    /// The visuals `progress` of the way from `from` to `to` (0 is `from`, 1 is `to`; a spring
    /// passes 1 and comes back).
    static func interpolated(_ from: BoxVisuals, _ to: BoxVisuals, _ progress: Double) -> BoxVisuals {
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * progress }
        func mix(_ a: Float, _ b: Float) -> Float { a + (b - a) * Float(progress) }
        var result = to
        if !from.hidden && !to.hidden {
            result.opacity = min(max(mix(from.opacity, to.opacity), 0), 1)
        }
        result.offsetX = mix(from.offsetX, to.offsetX)
        result.offsetY = mix(from.offsetY, to.offsetY)
        result.rotation = mix(from.rotation, to.rotation)
        result.scaleX = mix(from.scaleX, to.scaleX)
        result.scaleY = mix(from.scaleY, to.scaleY)
        result.enterOpacity = min(max(mix(from.enterOpacity, to.enterOpacity), 0), 1)
        result.enterScaleX = mix(from.enterScaleX, to.enterScaleX)
        result.enterScaleY = mix(from.enterScaleY, to.enterScaleY)
        result.enterMoveX = mix(from.enterMoveX, to.enterMoveX)
        result.enterMoveY = mix(from.enterMoveY, to.enterMoveY)
        result.enterOffsetX = mix(from.enterOffsetX, to.enterOffsetX)
        result.enterOffsetY = mix(from.enterOffsetY, to.enterOffsetY)
        if let start = from.shadow, let end = to.shadow {
            result.shadow = ShadowValue(red: min(max(mix(start.red, end.red), 0), 1),
                                        green: min(max(mix(start.green, end.green), 0), 1),
                                        blue: min(max(mix(start.blue, end.blue), 0), 1),
                                        alpha: min(max(mix(start.alpha, end.alpha), 0), 1),
                                        dx: mix(start.dx, end.dx), dy: mix(start.dy, end.dy),
                                        radius: max(mix(start.radius, end.radius), 0))
        }
        return result
    }
}

/// The animation state of one box: the trigger it saw last, what the model asks it to show, what
/// it shows now, and the animation between them. Attached to the outer box, so it lives as long
/// as the box.
@MainActor
final class BoxAnimator {
    /// The box, which owns this animator.
    private let box: WidgetPointer
    /// The trigger at the last sync; nil before the first one, or when the element declared no
    /// animation.
    var trigger: AnyHashable?
    /// What the model asks the box to show. A new box shows the defaults.
    private(set) var target = BoxVisuals()
    /// What the box shows now.
    private(set) var shown = BoxVisuals()
    private var from = BoxVisuals()
    /// The running animation (a playing AdwAnimation holds a reference to itself, so it is paused
    /// to stop it), and the delay before it starts.
    private var animation: RunningAnimation?
    private var delaySource: guint = 0
    private var easing: (Double) -> Double = { $0 }
    /// The timing of an insertion transition while it runs: a change of the model during it that
    /// does not animate goes on with it rather than cutting it short.
    private var entrance: AnimationTiming?

    init(box: WidgetPointer) {
        self.box = box
    }

    isolated deinit {
        stop()
    }

    /// Shows `visuals`: at once without `timing`, else animated from what the box shows. The same
    /// visuals as before leave a running animation alone; during an insertion transition, a change
    /// without a timing takes the transition's.
    func show(_ visuals: BoxVisuals, timing: AnimationTiming?) {
        guard visuals != target else { return }
        let timing = timing ?? (isAnimating ? entrance : nil)
        target = visuals
        stop()
        guard let timing, visuals != shown else {
            draw(visuals)
            return
        }
        start(from: shown, timing: timing)
    }

    /// Plays an insertion transition: from the target with the transition's state (`entering`'s
    /// enter values) to the target, whose enter values are at rest.
    func enter(_ entering: BoxVisuals, anchor: (x: Double, y: Double), timing: AnimationTiming) {
        if let layout = attached(on: box, key: boxLayoutKey) {
            layout.transitionAnchor = anchor
        }
        var initial = target
        initial.enterOpacity = entering.enterOpacity
        initial.enterScaleX = entering.enterScaleX
        initial.enterScaleY = entering.enterScaleY
        initial.enterMoveX = entering.enterMoveX
        initial.enterMoveY = entering.enterMoveY
        initial.enterOffsetX = entering.enterOffsetX
        initial.enterOffsetY = entering.enterOffsetY
        stop()
        entrance = timing
        start(from: initial, timing: timing)
    }

    private func start(from start: BoxVisuals, timing: AnimationTiming) {
        from = start
        // What changes at once (hidden, a shadow appearing or going) does so now.
        draw(BoxVisuals.interpolated(from, target, 0))
        if timing.delay > 0 {
            delaySource = runAfter(milliseconds: UInt32(min(timing.delay * 1000, Double(UInt32.max)).rounded())) { [weak self] in
                guard let self else { return }
                self.delaySource = 0
                self.play(timing)
            }
        } else {
            play(timing)
        }
    }

    /// Whether an animation runs or waits for its delay (for tests).
    var isAnimating: Bool {
        delaySource != 0 || animation.map { adw_animation_get_state($0.owned.typed()) == ADW_ANIMATION_PLAYING } ?? false
    }

    private func play(_ timing: AnimationTiming) {
        let step = Unmanaged.passRetained(WeakAnimator(self)).toOpaque()
        let target = adw_callback_animation_target_new(animationStep, step, releaseAnimationStep)
        let made: OwnedObject
        switch timing.curve {
        case let .bezier(x1, y1, x2, y2, duration):
            made = OwnedObject(adopting: OpaquePointer(adw_timed_animation_new(box, 0, 1, guint(max((duration * 1000).rounded(), 1)), target)!))
            adw_timed_animation_set_easing(made.opaquePointer, ADW_LINEAR)
            easing = { AnimationTiming.bezierValue(x1: x1, y1: y1, x2: x2, y2: y2, at: $0) }
        case let .spring(response, dampingRatio):
            // SwiftUI's spring: stiffness (2 pi / response)^2 for a mass of 1.
            let stiffness = (2 * Double.pi / response) * (2 * Double.pi / response)
            // The animation takes the parameters' reference, and the target's.
            let params = adw_spring_params_new(dampingRatio, 1, stiffness)!
            made = OwnedObject(adopting: OpaquePointer(adw_spring_animation_new(box, 0, 1, params, target)!))
            easing = { $0 }
        }
        connectSignal(made.pointer, "done", .instanceOnly) { [weak self] in
            guard let self else { return }
            self.entrance = nil
            self.draw(self.target)
        }
        let running = RunningAnimation(made)
        animation = running
        adw_animation_play(running.owned.typed())
    }

    /// One frame of the running animation: libadwaita's value, the share of the way gone.
    fileprivate func step(_ value: Double) {
        draw(BoxVisuals.interpolated(from, target, easing(value)))
    }

    private func stop() {
        if delaySource != 0 {
            g_source_remove(delaySource)
            delaySource = 0
        }
        if let running = animation, adw_animation_get_state(running.owned.typed()) == ADW_ANIMATION_PLAYING {
            adw_animation_pause(running.owned.typed())
        }
        animation = nil
    }

    /// Draws `visuals` on the box: its opacity, the transform its layout gives the content group,
    /// and its shadow.
    private func draw(_ visuals: BoxVisuals) {
        shown = visuals
        let opacity = visuals.hidden ? 0 : min(max(visuals.opacity * visuals.enterOpacity, 0), 1)
        // GTK keeps opacity in 8 bits (0.5 reads back as 0.502).
        if abs(gtk_widget_get_opacity(box) - opacity) > 1.0 / 255 {
            gtk_widget_set_opacity(box, opacity)
        }
        if let layout = attached(on: box, key: boxLayoutKey) {
            let offset = (x: visuals.offsetX, y: visuals.offsetY)
            let scale = (x: visuals.scaleX, y: visuals.scaleY)
            let enterScale = (x: visuals.enterScaleX, y: visuals.enterScaleY)
            let enterMove = (x: visuals.enterMoveX, y: visuals.enterMoveY)
            let enterOffset = (x: visuals.enterOffsetX, y: visuals.enterOffsetY)
            if layout.offset != offset || layout.rotation != visuals.rotation || layout.scale != scale
                || layout.transitionScale != enterScale || layout.transitionMove != enterMove
                || layout.transitionOffset != enterOffset {
                layout.offset = offset
                layout.rotation = visuals.rotation
                layout.scale = scale
                layout.transitionScale = enterScale
                layout.transitionMove = enterMove
                layout.transitionOffset = enterOffset
                gtk_widget_queue_allocate(box)
            }
        }
        if let state = attached(on: box, key: boxShadowKey), state.value != visuals.shadow {
            state.value = visuals.shadow
            gtk_widget_queue_draw(box)
        }
    }
}

let boxAnimatorKey = AttachKey<BoxAnimator>("actionui-animation")

/// One AdwAnimation's reference.
@MainActor
private final class RunningAnimation {
    let owned: OwnedObject
    init(_ owned: consuming OwnedObject) { self.owned = owned }
}

/// The animator behind a running animation's callback, held weakly: a playing animation outlives
/// its owner's release.
@MainActor
private final class WeakAnimator {
    weak var animator: BoxAnimator?
    init(_ animator: BoxAnimator) { self.animator = animator }
}

private let animationStep: @convention(c) (Double, gpointer?) -> Void = { value, data in
    guard let data else { return }
    let box = Unmanaged<WeakAnimator>.fromOpaque(data).takeUnretainedValue()
    MainActor.assumeIsolated { box.animator?.step(value) }
}

private let releaseAnimationStep: @convention(c) (gpointer?) -> Void = { data in
    guard let data else { return }
    Unmanaged<AnyObject>.fromOpaque(data).release()
}

@MainActor
enum BoxAnimation {
    /// What runs `node`'s animation (BaseModifiers.Animation.trigger); nil without one. Reads its
    /// view model only when it declares one.
    static func trigger(_ node: RenderNode, _ animation: BaseModifiers.Animation?) -> AnyHashable? {
        animation?.trigger(mutationToken: node.model.mutationToken, properties: node.properties,
                           states: node.model.states, value: node.model.value)
    }

    /// The timing this sync of `box` animates with: the animation's, when the box saw a different
    /// trigger at its sync before; nil for a sync that does not animate. Keeps the trigger for the
    /// next sync.
    static func timing(_ animation: BaseModifiers.Animation?, trigger: AnyHashable?, box: WidgetPointer) -> AnimationTiming? {
        let animator = self.animator(of: box)
        let previous = animator.trigger
        animator.trigger = animation == nil ? nil : trigger
        guard let animation, let previous, let trigger, previous != trigger else { return nil }
        return AnimationTiming(animation)
    }

    /// The animation of an insert: SwiftUI's withAnimation around it, .default (the smooth spring).
    static let insertTiming = AnimationTiming(curve: .spring(response: AnimationTiming.springResponse, dampingRatio: 1))

    /// The smallest scale a scale transition starts from: SwiftUI's .scale starts at 0.00001
    /// (measured, macOS 27), which keeps the transform invertible.
    static let smallestScale = 0.00001

    /// Plays `transition`'s insertion on `box`, which already shows the element at rest. Nothing for
    /// an identity transition.
    static func enter(_ box: WidgetPointer, _ transition: BaseModifiers.Transition) {
        var entering = BoxVisuals()
        var anchor = (x: 0.5, y: 0.5)
        addInsertion(transition, to: &entering, anchor: &anchor)
        guard entering != BoxVisuals() else { return }
        animator(of: box).enter(entering, anchor: anchor, timing: insertTiming)
    }

    /// Adds what `transition` does on insertion to `entering`'s enter values: combined
    /// transitions together, the insertion half of an asymmetric one.
    private static func addInsertion(_ transition: BaseModifiers.Transition, to entering: inout BoxVisuals,
                                     anchor: inout (x: Double, y: Double)) {
        switch transition {
        case .identity:
            break
        case .opacity:
            entering.enterOpacity = 0
        case .slide:
            // SwiftUI's slide comes in from the leading edge (and leaves to the trailing one).
            entering.enterMoveX -= 1
        case let .scale(factor, name):
            var scale = factor.flatMap { $0.isFinite ? $0 : nil } ?? smallestScale
            if abs(scale) < smallestScale {
                scale = scale < 0 ? -smallestScale : smallestScale
            }
            entering.enterScaleX *= scale
            entering.enterScaleY *= scale
            anchor = ModifierBox.unitPoint(name)
        case let .move(edge):
            switch edge {
            case .top: entering.enterMoveY -= 1
            case .bottom: entering.enterMoveY += 1
            case .leading: entering.enterMoveX -= 1
            case .trailing: entering.enterMoveX += 1
            }
        case let .offset(x, y):
            if x.isFinite { entering.enterOffsetX += x }
            if y.isFinite { entering.enterOffsetY += y }
        case let .asymmetric(insertion, _):
            addInsertion(insertion, to: &entering, anchor: &anchor)
        case let .combined(parts):
            for part in parts {
                addInsertion(part, to: &entering, anchor: &anchor)
            }
        }
    }

    /// Shows `visuals` on `box`, animated with `timing` (at once for nil).
    static func show(_ visuals: BoxVisuals, on box: WidgetPointer, timing: AnimationTiming?) {
        animator(of: box).show(visuals, timing: timing)
    }

    /// The box's animator, made the first time.
    static func animator(of box: WidgetPointer) -> BoxAnimator {
        if let existing = attached(on: box, key: boxAnimatorKey) {
            return existing
        }
        let made = BoxAnimator(box: box)
        attach(made, to: box, key: boxAnimatorKey)
        return made
    }
}
