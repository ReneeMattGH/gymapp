package com.gymapp.android.widget

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class WidgetSettingsTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Before
    fun clear() {
        context.getSharedPreferences("forma.widgets", Context.MODE_PRIVATE).edit().clear().commit()
    }

    @Test
    fun `focus defaults to automatic and round-trips per widget`() {
        assertEquals(WidgetFocus.AUTOMATIC, WidgetSettings.focus(context, 1))
        WidgetSettings.setFocus(context, 1, WidgetFocus.WEEKLY)
        WidgetSettings.setFocus(context, 2, WidgetFocus.CONSISTENCY)

        assertEquals(WidgetFocus.WEEKLY, WidgetSettings.focus(context, 1))
        assertEquals(WidgetFocus.CONSISTENCY, WidgetSettings.focus(context, 2))

        WidgetSettings.clearFocus(context, 1)
        assertEquals(WidgetFocus.AUTOMATIC, WidgetSettings.focus(context, 1))
        assertEquals(WidgetFocus.CONSISTENCY, WidgetSettings.focus(context, 2))
    }

    @Test
    fun `unknown focus values fall back to automatic`() {
        context.getSharedPreferences("forma.widgets", Context.MODE_PRIVATE)
            .edit().putString("focus.7", "something-else").commit()
        assertEquals(WidgetFocus.AUTOMATIC, WidgetSettings.focus(context, 7))
    }

    @Test
    fun `publication timestamp is absent until the app publishes`() {
        assertNull(WidgetSettings.lastPublishedAt(context))
        WidgetSettings.markPublished(context, 1_700_000_000_000L)
        assertEquals(1_700_000_000_000L, WidgetSettings.lastPublishedAt(context))
    }
}
