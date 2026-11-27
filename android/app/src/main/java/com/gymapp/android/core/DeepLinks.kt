package com.gymapp.android.core

import android.net.Uri

enum class AppDeepLink {
    TODAY, START_WORKOUT, WORKOUTS, PROGRESS, COMMUNITY, CONNECTION_REQUESTS, MESSAGES, NOTIFICATIONS;

    companion object {
        fun parse(uri: Uri?): AppDeepLink? {
            if (uri == null || !uri.scheme.equals("forma", ignoreCase = true)) return null
            val host = uri.host?.lowercase() ?: ""
            val path = uri.pathSegments.map { it.lowercase() }
            return when {
                host == "today" && path.isEmpty() -> TODAY
                host == "start-workout" && path.isEmpty() -> START_WORKOUT
                (host == "workouts" || host == "plan") && path.isEmpty() -> WORKOUTS
                host == "progress" && path.isEmpty() -> PROGRESS
                host == "community" && path.isEmpty() -> COMMUNITY
                host == "community" && path == listOf("requests") -> CONNECTION_REQUESTS
                host == "community" && path == listOf("messages") -> MESSAGES
                host == "community" && path == listOf("notifications") -> NOTIFICATIONS
                else -> null
            }
        }
    }
}

/** Password-reset links from the backend's email. Email verification is a code. */
sealed interface AuthDeepLink {
    data class ResetPassword(val token: String) : AuthDeepLink

    companion object {
        fun parse(uri: Uri?): AuthDeepLink? {
            if (uri == null || !uri.scheme.equals("forma", ignoreCase = true)) return null
            val host = uri.host?.lowercase() ?: return null
            val path = uri.pathSegments.map { it.lowercase() }
            val token = uri.getQueryParameter("token")?.takeIf { it.isNotEmpty() } ?: return null
            return if (host == "auth" && path == listOf("reset-password")) ResetPassword(token) else null
        }
    }
}
