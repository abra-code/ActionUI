package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.ProvidableCompositionLocal
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.navigation.NavController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Common.applyCommonProperties
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import com.abracode.actionui.Helpers.ToolbarHost
import com.abracode.actionui.Helpers.stringProperty

/**
 * Push navigation. Mirror of the Apple `NavigationStack` element
 * (`ActionUI/Views/NavigationStack.swift`), which wraps `SwiftUI.NavigationStack`.
 * On Android it is backed by the **native** Jetpack Navigation Compose
 * [NavHost] (chosen over a hand-rolled back-stack so we inherit system-back
 * handling, transitions, and saved-state restoration for free).
 *
 * Named containers:
 *   * `content` - the root view shown at the bottom of the stack.
 *   * `destinations` - the array of push targets, each addressed by its `id`.
 *
 * NavHost's model is "destinations are routes declared up front," so the whole
 * `destinations` array maps to a single parameterized route - `dest/{id}` -
 * whose body resolves the element by id at render time ([buildDestinationMap]).
 * This handles any number of destinations without knowing their ids in advance.
 *
 * **Two Apple forms, one renderer.**
 *   * **By reference** (`NavigationLink`/sidebar row with `destinationViewId` ->
 *     `destinations`): the native-fit form; the link just navigates `dest/{id}`.
 *   * **Inline destination** (`NavigationLink` carrying a `destination` view):
 *     NavHost has no inline-destination concept, so inline destinations are
 *     **hoisted** into the same id-keyed registry by [buildDestinationMap]
 *     (scanning `content`). The only constraint vs. Apple is that an inline
 *     destination must carry an `id` to be addressable as a route.
 *
 * **State (`navigationPath`).** Like Apple, the current path is exposed as the
 * `navigationPath` element state - a `List<Int>` of the destination ids on the
 * stack (empty at root) - seeded empty by [initialStates] and kept in sync with
 * the [NavController] both ways: user navigation/back writes the state (host can
 * read it), and a host write of the state reconciles the controller (programmatic
 * push/pop). Each side compares before acting, so the two do not loop.
 *
 * `navigationTitle` (a base property on `content`/destination views) renders as a
 * simple header for now; the real navigation bar arrives with the toolbar track.
 */
object NavigationStack : ActionUIViewConstruction {

    /** Element-state key holding the push path as `List<Int>` (Apple parity). */
    const val NAVIGATION_PATH_KEY = "navigationPath"

    override fun initialStates(element: ActionUIElement): Map<String, Any> =
        mapOf(NAVIGATION_PATH_KEY to emptyList<Int>())

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val content = element.content
        val destinations = remember(element) { buildDestinationMap(element) }
        val navController = rememberNavController()
        val viewModel = LocalWindowModel.current?.viewModels?.get(element.id)

        val push: (Int) -> Unit = { id ->
            if (destinations.containsKey(id)) {
                navController.navigate(NAV_DEST_ROUTE_PREFIX + id)
            } else {
                logger.log("NavigationLink target id $id is not in this stack's destinations", LoggerLevel.warning)
            }
        }

        // Forward sync: user navigation/back -> navigationPath state (host reads it).
        LaunchedEffect(navController, viewModel) {
            if (viewModel == null) return@LaunchedEffect
            navController.currentBackStackEntryFlow.collect {
                val path = currentDestinationPath(navController)
                @Suppress("UNCHECKED_CAST")
                val existing = viewModel.states[NAVIGATION_PATH_KEY] as? List<Int> ?: emptyList()
                if (existing != path) viewModel.states[NAVIGATION_PATH_KEY] = path
            }
        }

        // Backward sync: a host write of navigationPath -> reconcile the controller.
        // Reading the state here subscribes this composable, so a host setElementState
        // re-runs the effect. Best-effort: rebuild the path from root.
        @Suppress("UNCHECKED_CAST")
        val desiredPath = (viewModel?.states?.get(NAVIGATION_PATH_KEY) as? List<Int>) ?: emptyList()
        LaunchedEffect(desiredPath) {
            if (currentDestinationPath(navController) != desiredPath) {
                navController.popBackStack(NAV_ROOT_ROUTE, inclusive = false)
                desiredPath.forEach { id ->
                    if (destinations.containsKey(id)) navController.navigate(NAV_DEST_ROUTE_PREFIX + id)
                }
            }
        }

        CompositionLocalProvider(LocalNavPush provides push) {
            NavHost(navController = navController, startDestination = NAV_ROOT_ROUTE, modifier = modifier) {
                composable(NAV_ROOT_ROUTE) {
                    RenderNavChild(content, logger)
                }
                composable(
                    route = NAV_DEST_ROUTE_PREFIX + "{$NAV_ARG_ID}",
                    arguments = listOf(navArgument(NAV_ARG_ID) { type = NavType.IntType }),
                ) { entry ->
                    val id = entry.arguments?.getInt(NAV_ARG_ID)
                    val destination = id?.let { destinations[it] }
                    if (destination != null) {
                        RenderNavChild(destination, logger)
                    } else {
                        logger.log("No destination element for id $id", LoggerLevel.warning)
                    }
                }
            }
        }
    }
}

private const val NAV_ROOT_ROUTE = "actionui/nav/root"
private const val NAV_DEST_ROUTE_PREFIX = "actionui/nav/dest/"
private const val NAV_ARG_ID = "destId"

/**
 * Push callback provided by the enclosing [NavigationStack]: pushes the
 * destination with the given id. Defaults to a no-op so a `NavigationLink`
 * rendered outside a stack degrades gracefully (it warns on tap instead).
 */
val LocalNavPush: ProvidableCompositionLocal<(Int) -> Unit> = staticCompositionLocalOf { {} }

/**
 * The id-keyed push-target registry for a [NavigationStack]: every
 * `destinations[]` entry (explicit, wins on conflict) plus every inline
 * `destination` hoisted from the `content` subtree (Apple's inline-link form).
 * Entries without a positive id are skipped (NavHost addresses by id). Pure, so
 * it is unit-testable.
 */
internal fun buildDestinationMap(stack: ActionUIElement): Map<Int, ActionUIElement> {
    val map = LinkedHashMap<Int, ActionUIElement>()
    stack.content?.let { collectInlineDestinations(it, map) }
    // destinations[] is authoritative: overwrite any inline entry sharing an id.
    stack.destinations?.forEach { if (it.id != 0) map[it.id] = it }
    return map
}

private fun collectInlineDestinations(element: ActionUIElement, into: MutableMap<Int, ActionUIElement>) {
    element.destination?.let { dest ->
        if (dest.id != 0) into.putIfAbsent(dest.id, dest)
        collectInlineDestinations(dest, into)
    }
    element.children?.forEach { collectInlineDestinations(it, into) }
    element.content?.let { collectInlineDestinations(it, into) }
}

/** The destination ids currently on the back stack, root-to-top (empty at root). */
private fun currentDestinationPath(navController: NavController): List<Int> =
    navController.currentBackStack.value.mapNotNull { entry ->
        if (entry.destination.route?.startsWith(NAV_DEST_ROUTE_PREFIX) == true) {
            entry.arguments?.getInt(NAV_ARG_ID)
        } else {
            null
        }
    }

/**
 * Renders one navigation child (root content or a destination) through the normal
 * pipeline. When the element declares a `toolbar` or a `navigationTitle`, the body
 * is wrapped in a [ToolbarHost] (a `Scaffold` + `TopAppBar` / `BottomAppBar`); see
 * `Helpers/ToolbarHelper.kt`. Otherwise it renders bare.
 */
@Composable
private fun RenderNavChild(element: ActionUIElement?, logger: ActionUILogger) {
    if (element == null) return
    val builder = ActionUIRegistry.lookup(element.type) ?: return
    val body: @Composable () -> Unit = {
        ProvideTextStyleEnvironment(element.properties, logger) {
            builder.BuildView(element, Modifier.applyCommonProperties(element.properties, logger))
        }
    }
    val hasChrome = element.toolbar != null ||
        element.properties?.stringProperty("navigationTitle") != null
    if (hasChrome) {
        ToolbarHost(element, logger) { inner -> Box(Modifier.padding(inner)) { body() } }
    } else {
        body()
    }
}
