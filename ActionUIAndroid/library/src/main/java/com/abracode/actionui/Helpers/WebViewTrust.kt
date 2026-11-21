package com.abracode.actionui.Helpers

import com.abracode.actionui.Common.ActionUICapability
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.DefaultTrustPolicy
import com.abracode.actionui.Common.JSONContentOrigin
import com.abracode.actionui.Common.LoggerLevel

/**
 * What a WebView loads, by the trust policy, for content of a given origin: an address it may
 * not show is replaced by a short "Blocked" page, inline html gets a base address only when
 * the policy allows it, and a less-trusted page's own navigations are decided by
 * [navigation]. Mirrors the Swift `WebViewTrust`.
 */
internal object WebViewTrust {
    const val BLANK_BASE = "about:blank"

    /** The schemes a page uses inside itself, which stay in the WebView. */
    val pageSchemes: Set<String> = setOf("about", "data", "blob")

    /** What a less-trusted WebView does with a navigation its page starts. */
    enum class Navigation {
        /** Load it in the WebView. */
        LOAD,
        /** Hand it to the system (another app). */
        OPEN,
        /** Neither (logged). */
        REFUSE,
    }

    /** Whether the WebView of content of [origin] may show [url]; a refusal is logged. */
    fun showsAddress(url: String, origin: JSONContentOrigin, logger: ActionUILogger): Boolean {
        if (ActionUIModel.allows(ActionUICapability.WebView(url), origin)) return true
        logger.log("WebView not showing $url: the trust policy refuses it", LoggerLevel.warning)
        return false
    }

    /** Whether the WebView of content of [origin] may show inline html; a refusal is logged. */
    fun showsHTML(origin: JSONContentOrigin, logger: ActionUILogger): Boolean {
        if (ActionUIModel.allows(ActionUICapability.WebView(null), origin)) return true
        logger.log("WebView not showing its inline html: the trust policy refuses it", LoggerLevel.warning)
        return false
    }

    /** The base address for inline html: [base] when the policy allows it, else about:blank (none stays none). */
    fun base(base: String?, origin: JSONContentOrigin, logger: ActionUILogger): String? {
        if (base == null || base == BLANK_BASE) return base
        if (ActionUIModel.allows(ActionUICapability.WebViewBaseURL(base), origin)) return base
        logger.log("WebView html not given the base $base: the trust policy refuses it", LoggerLevel.warning)
        return BLANK_BASE
    }

    /**
     * What a less-trusted WebView does with a navigation to [url] ([isMainFrame]: the page
     * itself, not a frame in it): a web address loads when the policy shows it (a frame's
     * always does, as part of the page); the page's own schemes load, and a local file when the
     * policy shows it; any other address is opened by the system only when the policy allows a
     * link to it (mailto, by default), else refused.
     */
    fun navigation(url: String, isMainFrame: Boolean, origin: JSONContentOrigin, logger: ActionUILogger): Navigation {
        val scheme = DefaultTrustPolicy.schemeOf(url)
        val allows = { capability: ActionUICapability -> ActionUIModel.allows(capability, origin) }
        if (scheme == "http" || scheme == "https") {
            if (!isMainFrame || allows(ActionUICapability.WebView(url))) return Navigation.LOAD
        } else if (scheme in pageSchemes) {
            return Navigation.LOAD
        } else if (scheme == "file" && allows(ActionUICapability.WebView(url))) {
            return Navigation.LOAD
        } else if (isMainFrame && allows(ActionUICapability.OpenLink(url))) {
            // The page itself only: a frame (which a page can add without end) opens no other app.
            return Navigation.OPEN
        }
        logger.log("WebView not going to $url: the trust policy refuses it", LoggerLevel.warning)
        return Navigation.REFUSE
    }

    /** The page shown in place of an address the policy refuses. */
    fun blockedPage(url: String): String {
        val text = url.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")
        return "<!DOCTYPE html><meta charset=\"utf-8\"><p style=\"font-family: sans-serif\">Blocked: $text</p>"
    }
}
