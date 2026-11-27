package com.gymapp.android.widget

import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.gymapp.android.R
import com.gymapp.android.ui.components.PrimaryButton
import com.gymapp.android.ui.theme.FormaTheme
import com.gymapp.android.ui.theme.Radius
import com.gymapp.android.ui.theme.bodyFont
import com.gymapp.android.ui.theme.displayFont

/** Hosts the small-widget emphasis picker the launcher opens while placing the widget. */
class FitnessWidgetConfigureActivity : ComponentActivity() {
    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)
        appWidgetId = intent?.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }
        setContent {
            FormaTheme {
                val colors = FormaTheme.colors
                var selected by remember { mutableStateOf(WidgetSettings.focus(this, appWidgetId)) }
                val options = listOf(
                    WidgetFocus.AUTOMATIC to (
                        getString(R.string.widget_config_automatic) to
                            getString(R.string.widget_config_automatic_detail)
                        ),
                    WidgetFocus.TODAY to (
                        getString(R.string.widget_config_today) to
                            getString(R.string.widget_config_today_detail)
                        ),
                    WidgetFocus.WEEKLY to (
                        getString(R.string.widget_config_weekly) to
                            getString(R.string.widget_config_weekly_detail)
                        ),
                    WidgetFocus.CONSISTENCY to (
                        getString(R.string.widget_config_consistency) to
                            getString(R.string.widget_config_consistency_detail)
                        ),
                )
                Surface(modifier = Modifier.fillMaxSize(), color = colors.background) {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .systemBarsPadding()
                            .padding(horizontal = 24.dp, vertical = 20.dp),
                    ) {
                        Text(
                            text = getString(R.string.widget_config_title),
                            style = displayFont(24f, FontWeight.Bold),
                            color = colors.text,
                        )
                        Spacer(Modifier.height(6.dp))
                        Text(
                            text = getString(R.string.widget_config_body),
                            style = bodyFont(13f),
                            color = colors.textSecondary,
                        )
                        Spacer(Modifier.height(18.dp))
                        options.forEach { (focus, copy) ->
                            val (label, detail) = copy
                            val isSelected = selected == focus
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(Radius.md))
                                    .background(if (isSelected) colors.surface else Color.Transparent)
                                    .clickable { selected = focus }
                                    .padding(horizontal = 8.dp, vertical = 8.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                RadioButton(
                                    selected = isSelected,
                                    onClick = { selected = focus },
                                    colors = RadioButtonDefaults.colors(
                                        selectedColor = colors.accentText,
                                        unselectedColor = colors.textTertiary,
                                    ),
                                )
                                Column(Modifier.padding(start = 6.dp)) {
                                    Text(
                                        text = label,
                                        style = bodyFont(14f, FontWeight.Medium),
                                        color = colors.text,
                                    )
                                    Text(
                                        text = detail,
                                        style = bodyFont(11.5f),
                                        color = colors.textTertiary,
                                    )
                                }
                            }
                        }
                        Spacer(Modifier.weight(1f))
                        PrimaryButton(
                            title = getString(R.string.widget_config_save),
                            modifier = Modifier.fillMaxWidth(),
                            onClick = { save(selected) },
                        )
                    }
                }
            }
        }
    }

    private fun save(focus: WidgetFocus) {
        WidgetSettings.setFocus(this, appWidgetId, focus)
        WidgetUpdater.publish(this)
        setResult(
            RESULT_OK,
            Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId),
        )
        finish()
    }
}
