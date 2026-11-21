package com.abracode.actionui.Helpers

import com.abracode.actionui.Common.ActionUICapability
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUITrustPolicy
import com.abracode.actionui.Common.DefaultTrustPolicy
import com.abracode.actionui.Common.JSONContentOrigin
import com.abracode.actionui.Common.LoggerLevel
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** What a WebView of less-trusted content shows, which base its html gets, and where its page may go. */
class WebViewTrustTest {

    private class Recording : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings += message
        }
    }

    private val logger = Recording()
    private val remote = JSONContentOrigin(JSONContentOrigin.Source.Remote("https://example.com/v.json"), JSONContentOrigin.Trust.LESS_TRUSTED, 3)

    @After
    fun tearDown() {
        ActionUIModel.trustPolicy = DefaultTrustPolicy
    }

    @Test
    fun `less-trusted content shows only web addresses, the host's anything`() {
        assertTrue(WebViewTrust.showsAddress("https://example.com/", remote, logger))
        assertFalse(WebViewTrust.showsAddress("file:///sdcard/Download/a.html", remote, logger))
        assertFalse(WebViewTrust.showsAddress("javascript:alert(1)", remote, logger))
        assertEquals(2, logger.warnings.size)
        assertTrue(WebViewTrust.showsAddress("file:///android_asset/index.html", JSONContentOrigin.HOST, logger))
        assertTrue(WebViewTrust.showsHTML(remote, logger))
    }

    @Test
    fun `inline html keeps only its own document's origin as its base`() {
        assertEquals("https://example.com/page/", WebViewTrust.base("https://example.com/page/", remote, logger))
        assertEquals(WebViewTrust.BLANK_BASE, WebViewTrust.base("https://bank.example/", remote, logger))
        assertEquals(WebViewTrust.BLANK_BASE, WebViewTrust.base("file:///sdcard/", remote, logger))
        assertNull("no base stays none", WebViewTrust.base(null, remote, logger))
        assertEquals("https://bank.example/", WebViewTrust.base("https://bank.example/", JSONContentOrigin.HOST, logger))
    }

    @Test
    fun `a less-trusted page loads web addresses and its own schemes, opens mail, and goes nowhere else`() {
        fun nav(url: String, mainFrame: Boolean = true) = WebViewTrust.navigation(url, mainFrame, remote, logger)
        assertEquals(WebViewTrust.Navigation.LOAD, nav("https://other.example/"))
        assertEquals(WebViewTrust.Navigation.LOAD, nav("about:blank"))
        assertEquals(WebViewTrust.Navigation.LOAD, nav("data:text/html,hi"))
        assertEquals(WebViewTrust.Navigation.OPEN, nav("mailto:someone@example.com"))
        assertEquals(WebViewTrust.Navigation.REFUSE, nav("mailto:someone@example.com", mainFrame = false))
        assertEquals(WebViewTrust.Navigation.REFUSE, nav("intent://scan/#Intent;scheme=zxing;end"))
        assertEquals(WebViewTrust.Navigation.REFUSE, nav("file:///data/data/com.example/shared_prefs/a.xml"))
        assertEquals(WebViewTrust.Navigation.REFUSE, nav("content://com.android.contacts/contacts"))
    }

    @Test
    fun `the host's policy decides, for a WebView's address too`() {
        ActionUIModel.trustPolicy = object : ActionUITrustPolicy {
            override fun allows(capability: ActionUICapability, origin: JSONContentOrigin) =
                capability == ActionUICapability.WebView("file:///sdcard/manual.html") || DefaultTrustPolicy.allowsByDefault(capability, origin)
        }
        assertTrue(WebViewTrust.showsAddress("file:///sdcard/manual.html", remote, logger))
        assertEquals(WebViewTrust.Navigation.LOAD, WebViewTrust.navigation("file:///sdcard/manual.html", true, remote, logger))
    }

    @Test
    fun `the blocked page names the address as text`() {
        assertTrue(WebViewTrust.blockedPage("javascript:\"<b>&").contains("Blocked: javascript:&quot;&lt;b&gt;&amp;"))
    }
}
