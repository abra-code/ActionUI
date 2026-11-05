// Sources/Runtime/BoxAnimation.swift
/*
 The `animation` modifier on the GTK renderer.

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

    init(box: WidgetPointer) {
        self.box = box
    }

    isolated deinit {
        stop()
    }

    /// Shows `visuals`: at once without `timing`, else animated from what the box shows. The same
    /// visuals as before leave a running animation alone.
    func show(_ visuals: BoxVisuals, timing: AnimationTiming?) {
        guard visuals != target else { return }
        target = visuals
        stop()
        guard let timing, visuals != shown else {
            draw(visuals)
            return
        }
        from = shown
        // What changes at once (hidden, a shadow appearing or going) does so now.
        draw(BoxVisuals.interpolated(from, visuals, 0))
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
        let opacity = visuals.hidden ? 0 : min(max(visuals.opacity, 0), 1)
        // GTK keeps opacity in 8 bits (0.5 reads back as 0.502).
        if abs(gtk_widget_get_opacity(box) - opacity) > 1.0 / 255 {
            gtk_widget_set_opacity(box, opacity)
        }
        if let layout = attached(on: box, key: boxLayoutKey) {
            let offset = (x: visuals.offsetX, y: visuals.offsetY)
            let scale = (x: visuals.scaleX, y: visuals.scaleY)
            if layout.offset != offset || layout.rotation != visuals.rotation || layout.scale != scale {
                layout.offset = offset
                layout.rotation = visuals.rotation
                layout.scale = scale
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
