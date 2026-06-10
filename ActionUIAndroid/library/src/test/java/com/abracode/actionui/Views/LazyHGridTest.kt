package com.abracode.actionui.Views

import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

/**
 * Unit tests for [LazyHGrid]. The track parsing and cell-size math it rides on
 * are covered by `Helpers/GridTrackHelperTest`; the `@Composable` grid is
 * exercised by running the app, the stance the rest of the renderer takes.
 */
class LazyHGridTest {

    @Test
    fun `registry resolves LazyHGrid and it carries no value`() {
        assertSame(LazyHGrid, ActionUIRegistry.lookup("LazyHGrid"))
        assertEquals(ActionUIValueType.NONE, LazyHGrid.valueType)
    }
}
