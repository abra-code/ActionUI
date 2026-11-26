package com.abracode.actionui.Common

import androidx.compose.ui.platform.UriHandler
import java.io.File
import java.io.IOException
import java.net.URI
import java.net.URISyntaxException

/**
 * Something a part of a window's content may do, which the trust policy is asked about
 * ([ActionUIModel.allows]). The renderers ask before each. Mirrors the Swift
 * `ActionUICapability`.
 */
sealed interface ActionUICapability {
    /** A LoadableView loading this source (the size caps apply whatever the answer). */
    data class Load(val source: JSONContentOrigin.Source) : ActionUICapability
    /** Opening an address: a Link. */
    data class OpenLink(val url: String) : ActionUICapability
    /** A WebView showing this address; null for inline html. */
    data class WebView(val url: String?) : ActionUICapability
    /** The base address a WebView's inline html runs under (its origin, for cookies and storage). */
    data class WebViewBaseURL(val url: String) : ActionUICapability
    /** A WebView running the user scripts its content gives; refused, it runs none. Asked when the WebView is made, only when it has scripts. */
    data object WebViewUserScripts : ActionUICapability
    /**
     * A WebView keeping its data in the app's persistent store. Not asked on Android: an
     * Android WebView has the app's one cookie store (Apple and Linux give a refused WebView a
     * private one). Kept for the same table as the Swift `ActionUICapability`.
     */
    data object WebViewPersistentData : ActionUICapability
    /** A WebView user script read from this file. */
    data class WebViewScriptFile(val path: String) : ActionUICapability
    /** An Image, Canvas image, VideoPlayer or AsyncImage reading this local file. */
    data class ReadLocalFile(val path: String) : ActionUICapability
    /** A VideoPlayer playing this address that is not a local file (a local one is asked as [ReadLocalFile]). */
    data class PlayMedia(val url: String) : ActionUICapability
    /** Setting the window's title (navigationTitle). */
    data object WindowTitle : ActionUICapability
    /** Presenting a sheet, full-screen cover or popover of its own. */
    data object PresentModal : ActionUICapability
    /** Adding menu commands (none on Android today). */
    data object MenuCommands : ActionUICapability
    /** Firing this action. */
    data class Action(val actionID: String) : ActionUICapability
    /**
     * A HostSurface element (the hostsurface add-on) binding to the host's surface of this
     * name, so that the host's client draws in it and gets its input. Refused, it draws a
     * placeholder and the client never hears of it.
     */
    data class HostSurface(val surfaceName: String) : ActionUICapability
}

/**
 * The host's say over how far content is trusted and what it may do, set on
 * [ActionUIModel.trustPolicy] before loading. One object serves every window. Both methods
 * have defaults, so a host overrides only what it needs. They are called on the main thread,
 * often (as elements draw), and should return quickly. Mirrors the Swift `ActionUITrustPolicy`.
 */
interface ActionUITrustPolicy {
    /**
     * The trust of content loaded from [source] inside content of origin [parent] (null for
     * a window's root), given what ActionUI decides [byDefault]. The default keeps that.
     */
    fun trust(source: JSONContentOrigin.Source, parent: JSONContentOrigin?, byDefault: JSONContentOrigin.Trust): JSONContentOrigin.Trust =
        byDefault

    /** Whether content of [origin] may do [capability]. The default is [DefaultTrustPolicy]'s. */
    fun allows(capability: ActionUICapability, origin: JSONContentOrigin): Boolean =
        DefaultTrustPolicy.allowsByDefault(capability, origin)
}

/** ActionUI's own policy: trust as classified, and the default refusals for less-trusted content. */
object DefaultTrustPolicy : ActionUITrustPolicy {
    /** The schemes less-trusted content may open. */
    val linkSchemes: Set<String> = setOf("http", "https", "mailto")

    /** The schemes a less-trusted WebView may show. */
    val webViewSchemes: Set<String> = setOf("http", "https")

    /** The schemes besides file a less-trusted VideoPlayer may play. */
    val mediaSchemes: Set<String> = setOf("http", "https")

    /** The scheme of [address], lower-cased; empty when it has none (a relative address). */
    fun schemeOf(address: String): String {
        val colon = address.indexOf(':')
        if (colon <= 0) return ""
        val scheme = address.substring(0, colon)
        val valid = scheme[0].isLetter() && scheme.all { it.isLetterOrDigit() || it == '+' || it == '-' || it == '.' }
        return if (valid) scheme.lowercase() else ""
    }

    /** Whether the file at [path] is inside the app's resource folder ([ActionUIConfiguration.resourceFolder]), symbolic links followed. */
    fun isInAppResources(path: String): Boolean {
        val canonical = try { File(path).canonicalPath } catch (e: IOException) { return false }
        return ActionUIConfiguration.current.resourceFolders.any { isFileInside(canonical, it) }
    }

    /** Whether two addresses have the same origin: scheme, host and port (the scheme's default port when none is written). */
    fun haveSameOrigin(first: String, second: String): Boolean {
        fun origin(address: String): Triple<String, String, Int>? {
            val uri = try { URI(address) } catch (e: URISyntaxException) { return null }
            val scheme = uri.scheme?.lowercase() ?: return null
            val host = uri.host?.lowercase() ?: return null
            val port = if (uri.port != -1) uri.port else when (scheme) { "https" -> 443; "http" -> 80; else -> -1 }
            return Triple(scheme, host, port)
        }
        val a = origin(first) ?: return false
        val b = origin(second) ?: return false
        return a == b
    }

    /**
     * What content of [origin] may do when the host does not say: trusted content anything;
     * less-trusted content may open only web and mail links, show only web addresses in a
     * WebView, play only web addresses in a VideoPlayer (local files as below), give its
     * inline html a base address only of its own JSON's origin, run no
     * WebView user scripts, keep no WebView data in the app's persistent store, read
     * local files (images, videos, WebView script files) and load ActionUI JSON from local
     * files only inside the app's resource folders, neither set the title nor present its
     * own sheets, covers and popovers, and show no host surface.
     * The same table as the Swift `DefaultTrustPolicy.allowsByDefault`.
     */
    fun allowsByDefault(capability: ActionUICapability, origin: JSONContentOrigin): Boolean {
        if (origin.trust == JSONContentOrigin.Trust.TRUSTED) return true
        return when (capability) {
            is ActionUICapability.OpenLink -> schemeOf(capability.url) in linkSchemes
            is ActionUICapability.WebView -> capability.url == null || schemeOf(capability.url) in webViewSchemes
            is ActionUICapability.WebViewBaseURL -> {
                val remote = origin.source as? JSONContentOrigin.Source.Remote ?: return false
                haveSameOrigin(capability.url, remote.url)
            }
            ActionUICapability.WebViewUserScripts, ActionUICapability.WebViewPersistentData -> false
            is ActionUICapability.ReadLocalFile -> isInAppResources(capability.path)
            is ActionUICapability.WebViewScriptFile -> isInAppResources(capability.path)
            // Web addresses only: not content:, rtsp: or android.resource: addresses, which reach
            // other apps' data or servers the app does not name.
            is ActionUICapability.PlayMedia -> schemeOf(capability.url) in mediaSchemes
            ActionUICapability.WindowTitle, ActionUICapability.PresentModal -> false
            // The host's own drawing and input where content not the app's own puts it could pass for the app.
            is ActionUICapability.HostSurface -> false
            // A local file outside the app's resource folders is not loaded; resources and remote addresses are.
            is ActionUICapability.Load -> capability.source !is JSONContentOrigin.Source.File
            ActionUICapability.MenuCommands, is ActionUICapability.Action -> true
        }
    }
}

/** How many loads ([loads]) a window's LoadableViews may make in any [seconds]. */
data class LoadBudget(val loads: Int, val seconds: Double)

/** The origin of content loaded from [source] inside [parent]: classified ([classifyOrigin]), then the host's policy has the last word. */
internal fun resolvedOrigin(
    source: com.abracode.actionui.Helpers.LoadableSource,
    parent: JSONContentOrigin?,
    parentID: Int?,
): JSONContentOrigin? {
    val configuration = ActionUIConfiguration.current
    val classified = classifyOrigin(source, parent, parentID, configuration.resourceFolders, configuration.trust.trustedOrigins) ?: return null
    val trust = ActionUIModel.trustPolicy.trust(classified.source, parent, classified.trust)
    return if (trust == classified.trust) classified else classified.copy(trust = trust)
}

/**
 * The [UriHandler] for content of [origin]: [inner] itself for trusted content; for less-trusted
 * content one that hands on only an address the trust policy lets it open ([ActionUICapability.OpenLink])
 * and logs a refusal. Links in Markdown text (an add-on's LinkAnnotation) open through it.
 */
internal fun uriHandlerFor(origin: JSONContentOrigin, inner: UriHandler, logger: ActionUILogger): UriHandler {
    if (origin.trust == JSONContentOrigin.Trust.TRUSTED) return inner
    return object : UriHandler {
        override fun openUri(uri: String) {
            if (!ActionUIModel.allows(ActionUICapability.OpenLink(uri), origin)) {
                logger.log("Not opening $uri: the trust policy refuses it", LoggerLevel.warning)
                return
            }
            inner.openUri(uri)
        }
    }
}
