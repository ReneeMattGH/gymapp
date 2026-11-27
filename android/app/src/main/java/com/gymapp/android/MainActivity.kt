package com.gymapp.android

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.gymapp.android.core.AppDeepLink
import com.gymapp.android.core.AuthDeepLink
import com.gymapp.android.store.FormaViewModel
import com.gymapp.android.ui.FormaApp
import com.gymapp.android.widget.WidgetUpdater

class MainActivity : ComponentActivity() {
    private val model: FormaViewModel by viewModels()
    private var pendingDeepLink by mutableStateOf<AppDeepLink?>(null)
    private var pendingResetToken by mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        handleIntent(intent)
        setContent {
            FormaApp(
                model = model,
                deepLink = pendingDeepLink,
                onConsumeDeepLink = { pendingDeepLink = null },
                resetToken = pendingResetToken,
                onConsumeResetToken = { pendingResetToken = null },
            )
        }
    }

    override fun onResume() {
        super.onResume()
        // Recomputes "today" and the seven-day strip when the user returns.
        WidgetUpdater.refresh(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val uri = intent?.data ?: return
        when (val reset = AuthDeepLink.parse(uri)) {
            is AuthDeepLink.ResetPassword -> {
                pendingResetToken = reset.token
                return
            }
            null -> Unit
        }
        pendingDeepLink = AppDeepLink.parse(uri)
    }
}
