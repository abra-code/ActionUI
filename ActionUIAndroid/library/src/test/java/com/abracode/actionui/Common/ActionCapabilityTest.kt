package com.abracode.actionui.Common

import com.abracode.actionui.Helpers.ActionDispatch
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

/**
 * The trust policy is asked before an action fires ([ActionUICapability.Action]), with the origin
 * of the content that fires it: the one a renderer passes ([ActionDispatch]), else the host's for
 * viewID 0, else the element's recorded origin, less trusted when it has none. The default policy
 * fires every action.
 */
class ActionCapabilityTest {

    private val windowUUID = "action-capability-test"
    private val fired = mutableListOf<Int>()
    private val remote = JSONContentOrigin(JSONContentOrigin.Source.Remote("https://example.com/v.json"), JSONContentOrigin.Trust.LESS_TRUSTED, 3)

    @Before
    fun setUp() {
        ActionUIModel.trustPolicy = DefaultTrustPolicy
        ActionUIModel.registerActionHandler("test.run") { _, _, viewID, _, _ -> fired += viewID }
        val window = ActionUIModel.loadDescription(
            ActionUIElement(id = 1, type = "VStack", children = listOf(
                ActionUIElement(id = 2, type = "Button"),
                ActionUIElement(id = 3, type = "LoadableView"))),
            windowUUID = windowUUID,
        )
        window.loadSubDescription(ActionUIElement(id = 20, type = "Button"), parentID = 3, origin = remote)
    }

    @After
    fun tearDown() {
        ActionUIModel.trustPolicy = DefaultTrustPolicy
        ActionUIModel.unregisterActionHandler("test.run")
        ActionUIModel.unregisterWindow(windowUUID)
    }

    private fun fireAll() {
        for (viewID in listOf(2, 20, 0, 999)) ActionUIModel.actionHandler("test.run", windowUUID = windowUUID, viewID = viewID)
        ActionDispatch(windowUUID, remote).fire("test.run", viewID = -5)
        ActionDispatch(windowUUID, JSONContentOrigin.HOST).fire("test.run", viewID = -6)
    }

    @Test
    fun `the default policy fires every action`() {
        fireAll()
        assertEquals(listOf(2, 20, 0, 999, -5, -6), fired)
    }

    @Test
    fun `a policy that refuses an action has its way`() {
        val asked = mutableListOf<JSONContentOrigin.Trust>()
        ActionUIModel.trustPolicy = object : ActionUITrustPolicy {
            override fun allows(capability: ActionUICapability, origin: JSONContentOrigin): Boolean {
                if (capability !is ActionUICapability.Action) return DefaultTrustPolicy.allowsByDefault(capability, origin)
                asked += origin.trust
                return origin.trust == JSONContentOrigin.Trust.TRUSTED
            }
        }
        fireAll()
        assertEquals("the host's element, no element (0), and an element a renderer judged by the host's content", listOf(2, 0, -6), fired)
        assertEquals(
            listOf(
                JSONContentOrigin.Trust.TRUSTED, // 2: the host's element
                JSONContentOrigin.Trust.LESS_TRUSTED, // 20: the remote content's
                JSONContentOrigin.Trust.TRUSTED, // 0: the host
                JSONContentOrigin.Trust.LESS_TRUSTED, // 999: no view model
                JSONContentOrigin.Trust.LESS_TRUSTED, // a no-id element in remote content
                JSONContentOrigin.Trust.TRUSTED, // a no-id element in the host's content
            ),
            asked,
        )
    }

    @Test
    fun `an incoming URL fires with the origin of the content the element is in`() {
        ActionUIModel.trustPolicy = object : ActionUITrustPolicy {
            override fun allows(capability: ActionUICapability, origin: JSONContentOrigin): Boolean =
                capability !is ActionUICapability.Action || origin.trust == JSONContentOrigin.Trust.TRUSTED
        }
        // Elements with no id (viewID 0): one in remote content, one in the host's.
        val theirs = OpenURLObserver("test.run", windowUUID, 0, remote)
        val mine = OpenURLObserver("test.run", windowUUID, 0, JSONContentOrigin.HOST)
        ActionUIModel.registerOpenURLObserver(theirs)
        ActionUIModel.registerOpenURLObserver(mine)
        try {
            ActionUIModel.onOpenURL("https://example.com/x")
        } finally {
            ActionUIModel.unregisterOpenURLObserver(theirs)
            ActionUIModel.unregisterOpenURLObserver(mine)
        }
        assertEquals(listOf(0), fired)
    }
}
