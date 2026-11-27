package com.gymapp.android.core

import com.gymapp.android.BuildConfig

object AppConfig {
    /** Empty until a real backend origin is configured for this build. */
    val apiBaseUrl: String = BuildConfig.FORMA_API_URL.trimEnd('/')

    val isBackendConfigured: Boolean
        get() = apiBaseUrl.startsWith("https://") ||
            (BuildConfig.DEBUG && apiBaseUrl.startsWith("http://"))

    val buildChannel: String = BuildConfig.BUILD_CHANNEL
}
