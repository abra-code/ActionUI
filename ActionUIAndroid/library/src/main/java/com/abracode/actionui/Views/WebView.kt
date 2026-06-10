package com.abracode.actionui.Views

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.webkit.URLUtil
import android.webkit.WebChromeClient
import android.webkit.WebViewClient
import android.webkit.WebView as AndroidWebView
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Common.ViewModel
import com.abracode.actionui.Helpers.booleanProperty
import com.abracode.actionui.Helpers.stringProperty
import java.io.File
import java.io.InputStream
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Embedded web content. Mirror of the Apple `WebView` element
 * (`ActionUI/Views/WebView.swift`, SwiftUI `WebKit.WebView` / `WebPage`),
 * rendered as the real native [android.webkit.WebView] through Compose's
 * [AndroidView] interop - the renderer's first classic-View element, chosen
 * over any wrapper dependency because the platform WebView *is* the native
 * web element on Android.
 *
 * Sample JSON:
 * ```
 * {
 *   "type": "WebView",
 *   "id": 1,                                  // Positive id for the value/state bridge
 *   "properties": {
 *     "url": "https://www.swift.org",         // Optional: initial URL; wins over html
 *     "html": "<h1>Hello</h1>",               // Optional: inline HTML when url is absent
 *     "baseURL": "https://example.com",       // Optional: base for relative links in html
 *     "customUserAgent": "MyApp/1.0",         // Optional: user agent override
 *     "magnificationGestures": true,          // Optional: pinch-to-zoom; default true
 *     "userScripts": [                        // Optional: JS injected on each page load
 *       { "injectionTime": "documentStart",   //   "documentStart" | "documentEnd"
 *         "source": "window.myFlag = true;" } //   or "filePath" / "resourceName" (assets)
 *     ],
 *     "valueChangeActionID": "onURLChange",   // Optional: fired when the page URL changes
 *     "navigationActionID": "onNavigation",   // Optional: fired when loading starts/finishes
 *     "frame": { "height": 320 }              // A self-scrolling element: bound its height
 *   }
 * }
 * ```
 *
 * **Observable contract** (Apple's, key for key). `value` is the current page
 * URL; the host writes a URL string to navigate, or one of the commands
 * `#goBack` / `#goForward` / `#reload` / `#stop`. `states`: `title` (set after
 * the first load completes), `isLoading`, `estimatedProgress` (0.0..1.0),
 * `canGoBack`, `canGoForward`. Command strings never linger as the value - it
 * is reset to the current URL after the command runs, like the Apple side.
 *
 * **User scripts.** `source` (inline JS) / `filePath` (absolute path) /
 * `resourceName` (an asset name - the Android analog of Apple's main-bundle
 * lookup). Divergences, both inherent to the platform `WebView`:
 * `documentStart` is approximated by `evaluateJavascript` from
 * `WebViewClient.onPageStarted` - early in a remote load, but a fast inline
 * `html` page can finish parsing first (true pre-parse injection needs
 * androidx.webkit's `addDocumentStartJavaScript`, a dependency this element
 * deliberately avoids); and scripts run in the main frame only, so
 * `forMainFrameOnly: false` is accepted but cannot widen the scope.
 *
 * **Apple-only toggles** - accepted and silently ignored (documented here, the
 * `imageScale` precedent): `backForwardNavigationGestures` (Android navigates
 * back via the system back affordance, not an in-view swipe), `linkPreviews`
 * (no long-press preview), `limitsNavigationsToAppBoundDomains` and
 * `upgradeKnownHostsToHTTPS` (WebKit policies with no WebView equivalent).
 *
 * **Sizing.** Like every self-scrolling element here
 * ([[android-bounded-height-scroll]]), it needs a bounded height (an explicit
 * `frame`) when hosted in an unbounded scroll column.
 *
 * JavaScript is enabled, matching WebKit's default on the Apple side. Remote
 * URLs need the `INTERNET` permission (already required by `LoadableView`).
 */
object WebView : ActionUIViewConstruction {
    override val valueType = ActionUIValueType.STRING

    override fun initialValue(element: ActionUIElement): Any? =
        element.properties?.stringProperty("url") ?: ""

    override fun initialStates(element: ActionUIElement): Map<String, Any> = mapOf(
        "isLoading" to false,
        "estimatedProgress" to 0.0,
        "canGoBack" to false,
        "canGoForward" to false,
    )

    @SuppressLint("SetJavaScriptEnabled")
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        val logger = LocalActionUILogger.current
        val viewModel = LocalWindowModel.current?.viewModels?.get(element.id)
        val config = remember(props) { resolveWebViewConfig(props, logger) }

        // The classic-View handle, for the host-command effect below.
        var webView by remember { mutableStateOf<AndroidWebView?>(null) }
        // The last URL this element reported into the model itself, so a host
        // write can be told apart from our own report-back (Apple's
        // lastTrackedURL). Starts as the seeded value: the initial load is done
        // by the factory, not the command bridge.
        val lastTrackedURL = remember { mutableStateOf((viewModel?.value as? String).orEmpty()) }

        AndroidView(
            modifier = modifier,
            factory = { context ->
                AndroidWebView(context).apply {
                    settings.javaScriptEnabled = true
                    config.customUserAgent?.let { settings.userAgentString = it }
                    settings.setSupportZoom(config.magnificationGestures)
                    settings.builtInZoomControls = config.magnificationGestures
                    settings.displayZoomControls = false

                    // Script sources resolve once per view instance (assets need
                    // the Context); failures warn and drop the script, like the
                    // Apple bundle lookup.
                    val startScripts = config.userScripts
                        .filter { it.injectionTime == WebViewInjectionTime.DOCUMENT_START }
                        .mapNotNull { resolveScriptSource(it, context.assets::open, logger) }
                    val endScripts = config.userScripts
                        .filter { it.injectionTime == WebViewInjectionTime.DOCUMENT_END }
                        .mapNotNull { resolveScriptSource(it, context.assets::open, logger) }

                    webViewClient = object : WebViewClient() {
                        override fun onPageStarted(view: AndroidWebView, url: String?, favicon: Bitmap?) {
                            viewModel?.states?.set("isLoading", true)
                            startScripts.forEach { view.evaluateJavascript(it, null) }
                            fireNavigationAction(config, element)
                        }

                        override fun onPageFinished(view: AndroidWebView, url: String?) {
                            viewModel?.states?.let { states ->
                                states["isLoading"] = false
                                states["canGoBack"] = view.canGoBack()
                                states["canGoForward"] = view.canGoForward()
                                view.title?.let { states["title"] = it }
                            }
                            endScripts.forEach { view.evaluateJavascript(it, null) }
                            fireNavigationAction(config, element)
                            reportURL(url, view, viewModel, lastTrackedURL, config, element)
                        }

                        override fun doUpdateVisitedHistory(view: AndroidWebView, url: String?, isReload: Boolean) {
                            viewModel?.states?.let { states ->
                                states["canGoBack"] = view.canGoBack()
                                states["canGoForward"] = view.canGoForward()
                            }
                            reportURL(url, view, viewModel, lastTrackedURL, config, element)
                        }
                    }

                    webChromeClient = object : WebChromeClient() {
                        override fun onProgressChanged(view: AndroidWebView, newProgress: Int) {
                            viewModel?.states?.set("estimatedProgress", newProgress / 100.0)
                        }

                        override fun onReceivedTitle(view: AndroidWebView, title: String?) {
                            title?.let { viewModel?.states?.set("title", it) }
                        }
                    }

                    // Initial content: the seeded value (the `url` property, or a
                    // URL persisted across a document swap) wins over inline html,
                    // Apple's precedence. Neither -> the page stays blank.
                    val startURL = (viewModel?.value as? String)?.takeIf { it.isNotEmpty() } ?: config.url
                    when {
                        !startURL.isNullOrEmpty() -> loadUrl(startURL)
                        config.html != null -> loadDataWithBaseURL(
                            config.baseURL, config.html, "text/html", "utf-8", null
                        )
                    }
                }.also { webView = it }
            },
            onRelease = {
                if (webView === it) webView = null
                it.destroy()
            },
        )

        // Host-command bridge: a value written through setElementValue lands
        // here. Skips our own report-backs (value == lastTrackedURL).
        val command = viewModel?.value as? String
        LaunchedEffect(command) {
            val view = webView ?: return@LaunchedEffect
            if (viewModel == null || command.isNullOrEmpty() || command == lastTrackedURL.value) {
                return@LaunchedEffect
            }
            when (parseWebViewCommand(command)) {
                WebViewCommand.GO_BACK ->
                    if (view.canGoBack()) {
                        view.goBack()
                    } else {
                        logger.log("WebView goBack: no back item available", LoggerLevel.warning)
                        resetValueToCurrentURL(view, viewModel, lastTrackedURL)
                    }

                WebViewCommand.GO_FORWARD ->
                    if (view.canGoForward()) {
                        view.goForward()
                    } else {
                        logger.log("WebView goForward: no forward item available", LoggerLevel.warning)
                        resetValueToCurrentURL(view, viewModel, lastTrackedURL)
                    }

                WebViewCommand.RELOAD -> {
                    view.reload()
                    resetValueToCurrentURL(view, viewModel, lastTrackedURL)
                }

                WebViewCommand.STOP -> {
                    view.stopLoading()
                    resetValueToCurrentURL(view, viewModel, lastTrackedURL)
                }

                WebViewCommand.LOAD_URL ->
                    if (URLUtil.isValidUrl(command)) {
                        // The value is reported back by doUpdateVisitedHistory
                        // when the navigation lands.
                        view.loadUrl(command)
                    } else {
                        logger.log(
                            "WebView: unrecognized command or invalid URL '$command'; ignoring",
                            LoggerLevel.warning
                        )
                        resetValueToCurrentURL(view, viewModel, lastTrackedURL)
                    }
            }
        }
    }

    /** Pushes a navigated-to URL into the model and fires `valueChangeActionID`. */
    private fun reportURL(
        url: String?,
        view: AndroidWebView,
        viewModel: ViewModel?,
        lastTrackedURL: MutableState<String>,
        config: WebViewConfig,
        element: ActionUIElement,
    ) {
        val urlString = url ?: view.url ?: ""
        if (urlString == lastTrackedURL.value) return
        lastTrackedURL.value = urlString
        viewModel?.value = urlString
        if (config.valueChangeActionID != null && urlString.isNotEmpty()) {
            ActionUIModel.actionHandler(config.valueChangeActionID, viewID = element.id, viewPartID = 0)
        }
    }

    /** Resets the model value to the page URL so commands don't linger as the value. */
    private fun resetValueToCurrentURL(
        view: AndroidWebView,
        viewModel: ViewModel,
        lastTrackedURL: MutableState<String>,
    ) {
        val urlString = view.url ?: ""
        lastTrackedURL.value = urlString
        viewModel.value = urlString
    }

    private fun fireNavigationAction(config: WebViewConfig, element: ActionUIElement) {
        if (config.navigationActionID != null) {
            ActionUIModel.actionHandler(config.navigationActionID, viewID = element.id, viewPartID = 0)
        }
    }
}

// ---------------------------------------------------------------------------
// Pure configuration / command parsing (internal so unit tests can reach them;
// nothing below touches android.webkit, so the tests stay plain JVM).
// ---------------------------------------------------------------------------

/** When a user script is injected relative to the page load. */
internal enum class WebViewInjectionTime { DOCUMENT_START, DOCUMENT_END }

/** One validated `userScripts` entry; exactly one source field is non-null. */
internal data class WebViewUserScript(
    val injectionTime: WebViewInjectionTime,
    val source: String? = null,
    val filePath: String? = null,
    val resourceName: String? = null,
)

/** The element's validated properties, resolved once per `properties` change. */
internal data class WebViewConfig(
    val url: String? = null,
    val html: String? = null,
    val baseURL: String? = null,
    val customUserAgent: String? = null,
    val magnificationGestures: Boolean = true,
    val navigationActionID: String? = null,
    val valueChangeActionID: String? = null,
    val userScripts: List<WebViewUserScript> = emptyList(),
)

/** The host-command vocabulary written to `value`; anything else is a URL. */
internal enum class WebViewCommand { GO_BACK, GO_FORWARD, RELOAD, STOP, LOAD_URL }

internal fun parseWebViewCommand(raw: String): WebViewCommand = when (raw) {
    "#goBack" -> WebViewCommand.GO_BACK
    "#goForward" -> WebViewCommand.GO_FORWARD
    "#reload" -> WebViewCommand.RELOAD
    "#stop" -> WebViewCommand.STOP
    else -> WebViewCommand.LOAD_URL
}

/**
 * Validates the WebView properties, warn-and-skip with Apple's messages
 * (`WebView.swift` `validateProperties`). The Apple-only toggles are not read
 * at all (silently ignored - see the header).
 */
internal fun resolveWebViewConfig(props: JsonObject?, logger: ActionUILogger?): WebViewConfig {
    if (props == null) return WebViewConfig()

    fun string(key: String): String? {
        val raw = props[key] ?: return null
        if ((raw as? JsonPrimitive)?.isString != true) {
            logger?.log("WebView $key must be a String; ignoring", LoggerLevel.warning)
            return null
        }
        return raw.content
    }

    val magnification = props["magnificationGestures"]?.let { raw ->
        val value = (raw as? JsonPrimitive)?.let { props.booleanProperty("magnificationGestures") }
        if (value == null) {
            logger?.log("WebView magnificationGestures must be a Bool; ignoring", LoggerLevel.warning)
        }
        value
    } ?: true

    return WebViewConfig(
        url = string("url"),
        html = string("html"),
        baseURL = string("baseURL"),
        customUserAgent = string("customUserAgent"),
        magnificationGestures = magnification,
        navigationActionID = string("navigationActionID"),
        valueChangeActionID = string("valueChangeActionID"),
        userScripts = parseUserScripts(props["userScripts"], logger),
    )
}

/**
 * Parses the `userScripts` array: each entry needs one of `source` /
 * `filePath` / `resourceName` (else skipped with a warning); an invalid
 * `injectionTime` warns and defaults to `documentEnd`, the Apple validator's
 * behavior.
 */
internal fun parseUserScripts(raw: JsonElement?, logger: ActionUILogger?): List<WebViewUserScript> {
    if (raw == null) return emptyList()
    val array = raw as? JsonArray
    if (array == null) {
        logger?.log("WebView userScripts must be an array of dictionaries; ignoring", LoggerLevel.warning)
        return emptyList()
    }
    return array.mapIndexedNotNull { i, entry ->
        val script = entry as? JsonObject
        if (script == null) {
            logger?.log("WebView userScripts[$i] must be a dictionary; skipping", LoggerLevel.warning)
            return@mapIndexedNotNull null
        }
        val source = script.stringProperty("source")
        val filePath = script.stringProperty("filePath")
        val resourceName = script.stringProperty("resourceName")
        if (source == null && filePath == null && resourceName == null) {
            logger?.log(
                "WebView userScripts[$i] missing 'source', 'filePath', or 'resourceName'; skipping",
                LoggerLevel.warning
            )
            return@mapIndexedNotNull null
        }
        val time = when (val name = script.stringProperty("injectionTime")) {
            "documentStart" -> WebViewInjectionTime.DOCUMENT_START
            "documentEnd", null -> WebViewInjectionTime.DOCUMENT_END
            else -> {
                logger?.log(
                    "WebView userScripts[$i] injectionTime '$name' invalid; defaulting to 'documentEnd'",
                    LoggerLevel.warning
                )
                WebViewInjectionTime.DOCUMENT_END
            }
        }
        WebViewUserScript(time, source, filePath, resourceName)
    }
}

/**
 * Resolves a script descriptor to its JS text: inline `source` wins, then
 * `filePath` (absolute path), then `resourceName` opened through [openAsset]
 * (the Android analog of Apple's main-bundle lookup; tried as given, then with
 * `.js` appended). Read failures warn and drop the script.
 */
internal fun resolveScriptSource(
    script: WebViewUserScript,
    openAsset: (String) -> InputStream,
    logger: ActionUILogger?,
): String? {
    script.source?.let { return it }

    script.filePath?.let { path ->
        return try {
            File(path).readText()
        } catch (e: Exception) {
            logger?.log(
                "WebView userScript: failed to read file at '$path': ${e.message}",
                LoggerLevel.warning
            )
            null
        }
    }

    script.resourceName?.let { name ->
        val candidates = if (name.lowercase().endsWith(".js")) listOf(name) else listOf(name, "$name.js")
        for (candidate in candidates) {
            try {
                return openAsset(candidate).bufferedReader().use { it.readText() }
            } catch (_: Exception) {
                // Try the next candidate; warn below if none resolve.
            }
        }
        logger?.log("WebView userScript: asset '$name' not found", LoggerLevel.warning)
        return null
    }

    return null
}
