package com.abracode.actionui.Helpers

import androidx.compose.animation.VectorConverter as ColorVectorConverter
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.AnimationSpec
import androidx.compose.animation.core.AnimationVector1D
import androidx.compose.animation.core.AnimationVector4D
import androidx.compose.animation.core.EaseIn
import androidx.compose.animation.core.EaseInOut
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.VectorConverter
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Common.ViewModel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.math.PI
import kotlin.math.roundToInt
import kotlin.math.roundToLong

/**
 * The `animation` modifier - the host-driven-mutation animator, the Android
 * port of the Apple implementation in `ActionUI/Views/View.swift` (design:
 * `Private/Animation_Design.md`). An element declaring
 *
 * ```
 * "animation": "spring"                                  // shorthand
 * "animation": { "curve": "easeOut", "duration": 0.3,    // full form
 *                "delay": 0.1, "speed": 2, "value": "opacity" }
 * ```
 *
 * animates its visual property transitions when the host mutates it through
 * `ActionUIModel.setElementProperty` / `setElementState` / `setElementValue`.
 * The watched trigger is the named `value` key (a property, a state key, or the
 * literal `"value"`), or - when omitted - [ViewModel.mutationToken], Apple's
 * "animate any mutation" default. Nothing animates at load time; the first
 * composition snaps to the authored values (the Apple contract).
 *
 * **How it animates.** SwiftUI's `.animation(_:value:)` implicitly animates
 * every animatable property that changes with the watched value; Compose has no
 * implicit-animation modifier, so the mapping is explicit: the shared build
 * entry point (`ViewModifierHelper.kt`) creates one [ElementAnimator] per
 * decorated element and threads it into the common-property chain
 * (`ModifierResolver.kt`), where each animatable resolution - `opacity`,
 * `rotationEffect`, `scaleEffect`, `offset`, fixed `frame` width/height, and
 * the `background` color - reads its current value off a per-property
 * [Animatable] instead of using the target directly. When a target moves in
 * the same recomposition as the watched value, the [Animatable] springs/eases
 * to it; when it moves without the watched value (e.g. the document was
 * swapped), it snaps.
 *
 * **Curve mapping** (SwiftUI -> Compose): the duration curves (`linear`,
 * `easeIn`, `easeOut`, `easeInOut`) map to [tween] with the matching cubic
 * easing and SwiftUI's 0.35s default duration; the spring curves map to
 * [spring] with SwiftUI's damping fractions (`spring` 0.825, `bouncy` 0.7,
 * `smooth` 1.0, `snappy` 0.85, `interactiveSpring` 0.86, `default` 1.0) and
 * stiffness derived from the response time (`stiffness = (2*pi/response)^2`,
 * the standard spring-response relation; `duration` overrides the 0.5s default
 * response, and is ignored for `default` / `interactiveSpring` exactly as in
 * the Swift `resolveAnimation` switch). `speed` divides durations and delays
 * (and scales spring stiffness by `speed^2`, the time-scaling equivalent);
 * `delay` is applied by the driver coroutine, so it works for springs too
 * (Compose's per-spec delay exists only on [tween]).
 *
 * **Known divergences from SwiftUI** (documented, not silent):
 *   * Only the listed properties animate; SwiftUI also animates `padding`,
 *     `cornerRadius`, `shadow`, and flexible-frame changes. Extendable
 *     per-property as demos need them.
 *   * Text/content changes stay instant on both platforms (Apple's documented
 *     caveat: only animatable properties animate).
 *   * A child's own `animation` overrides the parent's for the child's chain
 *     (innermost wins, as on Apple) - but there is no cross-element animation
 *     inheritance: each element animates only its own declaration.
 */
internal data class AnimationConfig(
    val curve: String,
    val durationSec: Double? = null,
    val delaySec: Double = 0.0,
    val speed: Double = 1.0,
    val watchedKey: String? = null,
)

/** The curve vocabulary, matching the Swift `validAnimCurves` list. */
internal val VALID_ANIMATION_CURVES = setOf(
    "default", "linear", "easeIn", "easeOut", "easeInOut",
    "spring", "bouncy", "smooth", "snappy", "interactiveSpring",
)

/**
 * Parses the element's `animation` property into an [AnimationConfig], or null
 * when absent or invalid. Mirrors the Swift validation (`View.swift`): the
 * string shorthand normalizes to a curve-only config; in the dictionary form
 * `curve` is required (invalid -> the whole property is dropped with a warning)
 * and `duration` (positive) / `delay` (non-negative) / `speed` (positive) /
 * `value` (String) are each individually validated and dropped with a warning.
 */
internal fun resolveAnimationConfig(
    properties: JsonObject?,
    logger: ActionUILogger?,
): AnimationConfig? {
    val raw = properties?.get("animation") ?: return null

    if (raw is JsonPrimitive) {
        val curve = if (raw.isString) raw.content else null
        if (curve == null || curve !in VALID_ANIMATION_CURVES) {
            logger?.log(
                "Invalid animation curve '${properties.stringProperty("animation")}', " +
                    "expected one of $VALID_ANIMATION_CURVES, ignoring",
                LoggerLevel.warning
            )
            return null
        }
        return AnimationConfig(curve)
    }

    if (raw !is JsonObject) {
        logger?.log(
            "Invalid type for animation: expected String or Object, ignoring",
            LoggerLevel.warning
        )
        return null
    }

    val curve = raw.stringProperty("curve")
    if (curve == null || curve !in VALID_ANIMATION_CURVES) {
        logger?.log(
            "animation.curve '${curve ?: raw["curve"]}' must be one of $VALID_ANIMATION_CURVES, ignoring",
            LoggerLevel.warning
        )
        return null
    }

    var duration: Double? = null
    raw["duration"]?.let {
        val d = raw.numberProperty("duration")
        when {
            d == null -> logger?.log("Invalid animation.duration: expected positive Double, ignoring", LoggerLevel.warning)
            d <= 0 -> logger?.log("animation.duration must be positive, ignoring", LoggerLevel.warning)
            else -> duration = d
        }
    }

    var delaySec = 0.0
    raw["delay"]?.let {
        val d = raw.numberProperty("delay")
        if (d == null || d < 0) {
            logger?.log("Invalid animation.delay: expected non-negative Double, ignoring", LoggerLevel.warning)
        } else {
            delaySec = d
        }
    }

    var speed = 1.0
    raw["speed"]?.let {
        val s = raw.numberProperty("speed")
        if (s == null || s <= 0) {
            logger?.log("Invalid animation.speed: expected positive Double, ignoring", LoggerLevel.warning)
        } else {
            speed = s
        }
    }

    var watchedKey: String? = null
    raw["value"]?.let { v ->
        val s = (v as? JsonPrimitive)?.takeIf { it.isString }?.content
        if (s == null) {
            logger?.log("Invalid animation.value: expected String, ignoring", LoggerLevel.warning)
        } else {
            watchedKey = s
        }
    }

    return AnimationConfig(curve, duration, delaySec, speed, watchedKey)
}

/**
 * The standard second-order spring-response relation: a spring with this
 * stiffness (at the damping fractions above) settles on the same time scale as
 * a SwiftUI spring with response [responseSec].
 */
private fun stiffnessForResponse(responseSec: Double): Double =
    (2 * PI / responseSec) * (2 * PI / responseSec)

/** The [AnimationConfig] as a Compose spec for one animated value type. */
internal fun <T> AnimationConfig.animationSpec(): AnimationSpec<T> {
    val tweenMillis = (((durationSec ?: 0.35) / speed) * 1000).roundToInt()
    val speedSquared = speed * speed
    fun springSpec(dampingRatio: Float, defaultResponseSec: Double, honorsDuration: Boolean = true): AnimationSpec<T> {
        val response = if (honorsDuration) (durationSec ?: defaultResponseSec) else defaultResponseSec
        return spring(dampingRatio = dampingRatio, stiffness = (stiffnessForResponse(response) * speedSquared).toFloat())
    }
    return when (curve) {
        "linear" -> tween(tweenMillis, easing = LinearEasing)
        "easeIn" -> tween(tweenMillis, easing = EaseIn)
        "easeOut" -> tween(tweenMillis, easing = EaseOut)
        "easeInOut" -> tween(tweenMillis, easing = EaseInOut)
        "spring" -> springSpec(0.825f, 0.5)
        "bouncy" -> springSpec(0.7f, 0.5)
        "smooth" -> springSpec(1.0f, 0.5)
        "snappy" -> springSpec(0.85f, 0.5)
        "interactiveSpring" -> springSpec(0.86f, 0.15, honorsDuration = false)
        else -> springSpec(1.0f, 0.55, honorsDuration = false) // "default"
    }
}

/** The animation start delay in milliseconds, scaled by `speed` like durations. */
internal fun AnimationConfig.delayMillis(): Long = ((delaySec / speed) * 1000).roundToLong()

/**
 * The watched trigger value, resolved with the Swift
 * `resolveAnimationWatchedValue` lookup order: no named key -> the element's
 * [ViewModel.mutationToken] ("animate any mutation"); a named key -> the
 * effective property of that name (runtime overrides included via
 * [properties]), then a state key, then - for the literal `"value"` - the
 * element's runtime value; an unresolved key reads as a constant (no
 * animation), warned at parse time on Apple and here by the unchanging watch.
 *
 * Reads snapshot state ([ViewModel.mutationToken] / `states` / `value`), so a
 * composition calling this recomposes when the watched source changes.
 */
internal fun resolveAnimationWatchedValue(
    watchedKey: String?,
    viewModel: ViewModel?,
    properties: JsonObject?,
): Any? {
    if (watchedKey == null) return viewModel?.mutationToken ?: 0
    properties?.get(watchedKey)?.let { return it }
    viewModel?.states?.get(watchedKey)?.let { return it }
    if (watchedKey == "value") viewModel?.value?.let { return it }
    return 0
}

/**
 * Per-element animation state: one [Animatable] per animated chain value,
 * keyed by property name. Created by [rememberElementAnimator] and threaded
 * through `applyOuterProperties` / `applyInnerProperties`; the resolvers call
 * [float] / [dp] / [color] with the target they would otherwise apply
 * directly, and get back the current animated value (a snapshot read, so the
 * chain recomposes per animation frame, like `animate*AsState`).
 *
 * Target moves are recorded during composition and launched after it commits
 * ([Drive]'s `LaunchedEffect`, into a composition-scoped coroutine scope); a
 * new move for the same key cancels the one in flight, which is what makes a
 * mid-animation retarget track to the new value instead of queuing.
 */
class ElementAnimator internal constructor(internal val config: AnimationConfig) {

    private val floats = HashMap<String, Animatable<Float, AnimationVector1D>>()
    private val dps = HashMap<String, Animatable<Dp, AnimationVector1D>>()
    private val colors = HashMap<String, Animatable<Color, AnimationVector4D>>()

    /**
     * The most recently requested target per key. The schedule condition must
     * compare against this, NOT against `Animatable.targetValue`: the target
     * value only moves when the launched coroutine actually starts, so until
     * then every recomposition would re-schedule the same move - and each
     * re-schedule cancels the in-flight job, which starves any move whose
     * `delay` outlives a frame.
     */
    private val requestedTargets = HashMap<String, Any>()

    /** Moves recorded by the chain this composition, launched by [Drive]. */
    private val pendingMoves = ArrayList<Pair<String, suspend () -> Unit>>()
    private var pendingTick by mutableStateOf(0)
    private val runningJobs = HashMap<String, Job>()

    /** Sentinel distinguishing "never watched" from a null watched value. */
    private object NoWatch

    private var lastWatched: Any? = NoWatch
    private var animateThisPass = false

    /**
     * Called once per composition, before the chain resolves, with the current
     * watched value. The first composition seeds the watch without animating
     * (nothing animates at load time); afterwards, target moves animate exactly
     * when the watched value changed in the same recomposition - SwiftUI's
     * `.animation(_:value:)` transaction approximation - and snap otherwise.
     */
    fun onWatchedValue(watched: Any?) {
        animateThisPass = lastWatched !== NoWatch && watched != lastWatched
        lastWatched = watched
    }

    fun float(key: String, target: Float): Float {
        val animatable = floats.getOrPut(key) {
            requestedTargets[key] = target
            Animatable(target)
        }
        if (requestedTargets[key] != target) {
            requestedTargets[key] = target
            scheduleMove(key,
                animate = { animatable.animateTo(target, config.animationSpec()) },
                snap = { animatable.snapTo(target) },
            )
        }
        return animatable.value
    }

    fun dp(key: String, target: Dp): Dp {
        val animatable = dps.getOrPut(key) {
            requestedTargets[key] = target
            Animatable(target, Dp.VectorConverter)
        }
        if (requestedTargets[key] != target) {
            requestedTargets[key] = target
            scheduleMove(key,
                animate = { animatable.animateTo(target, config.animationSpec()) },
                snap = { animatable.snapTo(target) },
            )
        }
        return animatable.value
    }

    fun color(key: String, target: Color): Color {
        val animatable = colors.getOrPut(key) {
            requestedTargets[key] = target
            Animatable(target, (Color.ColorVectorConverter)(target.colorSpace))
        }
        if (requestedTargets[key] != target) {
            requestedTargets[key] = target
            scheduleMove(key,
                animate = { animatable.animateTo(target, config.animationSpec()) },
                snap = { animatable.snapTo(target) },
            )
        }
        return animatable.value
    }

    /**
     * Records one target move. Whether it animates is decided NOW (the
     * composition that moved the target), not when the coroutine runs.
     */
    private fun scheduleMove(key: String, animate: suspend () -> Unit, snap: suspend () -> Unit) {
        val shouldAnimate = animateThisPass
        pendingMoves += key to {
            if (shouldAnimate) {
                val delayMs = config.delayMillis()
                if (delayMs > 0) delay(delayMs)
                animate()
            } else {
                snap()
            }
        }
        pendingTick++
    }

    /**
     * Launches the moves recorded during this composition. A `LaunchedEffect`
     * keyed by the pending tick dispatches into a composition-scoped scope (so
     * running animations survive later recompositions), cancelling any
     * in-flight move for the same key first.
     */
    @Composable
    fun Drive() {
        val scope = rememberCoroutineScope()
        val tick = pendingTick
        LaunchedEffect(tick) {
            if (pendingMoves.isEmpty()) return@LaunchedEffect
            val work = pendingMoves.toList()
            pendingMoves.clear()
            for ((key, move) in work) {
                runningJobs[key]?.cancel()
                runningJobs[key] = launchMove(scope, move)
            }
        }
    }

    private fun launchMove(scope: CoroutineScope, move: suspend () -> Unit): Job =
        scope.launch { move() }
}

/**
 * The animator for [element]'s `animation` declaration, or null when it has
 * none (or an invalid one - warned by [resolveAnimationConfig]). Reads the
 * watched value (subscribing this composition to it) and hosts the [Drive]
 * effect. [element] should be the effective element (runtime property
 * overrides merged), so the watch and the chain targets move in the same
 * recomposition.
 */
@Composable
internal fun rememberElementAnimator(element: ActionUIElement): ElementAnimator? {
    val logger = LocalActionUILogger.current
    val properties = element.properties
    val config = remember(properties) { resolveAnimationConfig(properties, logger) } ?: return null
    val animator = remember(config) { ElementAnimator(config) }
    val viewModel = if (element.id > 0) LocalWindowModel.current?.viewModels?.get(element.id) else null
    animator.onWatchedValue(resolveAnimationWatchedValue(config.watchedKey, viewModel, properties))
    animator.Drive()
    return animator
}
