package com.abracode.actionui.addon.hostsurface

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.abracode.actionui.ActionUI
import com.abracode.actionui.Common.ActionUICapability
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUITrustPolicy
import com.abracode.actionui.Common.DefaultTrustPolicy
import com.abracode.actionui.Common.JSONContentOrigin
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * A surface the trust policy refuses (ActionUICapability.HostSurface) draws the placeholder: its client is never
 * told of it, while a surface the policy allows in the same window is announced as usual.
 */
@RunWith(AndroidJUnit4::class)
class HostSurfaceTrustTest {
    @get:Rule
    val rule = createComposeRule()

    private class Recorder : HostSurfaceDelegate {
        val events = mutableListOf<HostSurfaceEvent>()
        override fun onSurface(event: HostSurfaceEvent, info: HostSurfaceInfo) {
            events += event
        }
    }

    /** Refuses the surface name "test.refused" and keeps ActionUI's decisions otherwise. */
    private object RefusingPolicy : ActionUITrustPolicy {
        override fun allows(capability: ActionUICapability, origin: JSONContentOrigin): Boolean =
            if (capability == ActionUICapability.HostSurface("test.refused")) false
            else DefaultTrustPolicy.allowsByDefault(capability, origin)
    }

    private val window = "hostsurface-trust-${System.nanoTime()}"
    private val allowed = Recorder()
    private val refused = Recorder()
    private var savedPolicy: ActionUITrustPolicy = DefaultTrustPolicy

    private val document = """
        { "type": "VStack", "id": 1, "children": [
            { "type": "HostSurface", "id": 5, "properties": {
                "surfaceName": "test.allowed", "frame": { "width": 120, "height": 80 } } },
            { "type": "HostSurface", "id": 6, "properties": {
                "surfaceName": "test.refused", "frame": { "width": 120, "height": 80 } } }
        ] }
    """.trimIndent()

    @Before
    fun setUp() {
        HostSurfaceElement.register()
        savedPolicy = ActionUIModel.trustPolicy
        ActionUIModel.trustPolicy = RefusingPolicy
        rule.runOnIdle {
            assertTrue(HostSurfaces.setDelegate("test.allowed", allowed))
            assertTrue(HostSurfaces.setDelegate("test.refused", refused))
        }
    }

    @After
    fun tearDown() {
        rule.runOnIdle {
            HostSurfaces.setDelegate("test.allowed", null)
            HostSurfaces.setDelegate("test.refused", null)
        }
        ActionUIModel.trustPolicy = savedPolicy
    }

    @Test
    fun aRefusedSurfaceIsNeverAnnounced() {
        rule.setContent { ActionUI.Render(document, windowUUID = window) }
        rule.waitUntil(5_000) { allowed.events.isNotEmpty() }
        // The SurfaceHolder callbacks come on a later frame: give the refused one the same chance.
        Thread.sleep(300)
        rule.waitForIdle()
        assertEquals(HostSurfaceEvent.CREATED, allowed.events.first())
        assertEquals("the refused surface's client hears nothing", emptyList<HostSurfaceEvent>(), refused.events)
    }
}
