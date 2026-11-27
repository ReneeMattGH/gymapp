package com.gymapp.android.core

import java.util.UUID

object IDs {
    fun uuid(): String = UUID.randomUUID().toString().lowercase()
}

object StoredTimestamp {
    fun now(): Long = System.currentTimeMillis()
}
