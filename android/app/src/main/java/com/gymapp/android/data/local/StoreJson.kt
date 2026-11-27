package com.gymapp.android.data.local

import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

object StoreJson {
    val json: Json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
        encodeDefaults = true
    }

    fun <T> encode(serializer: KSerializer<T>, value: T): String =
        json.encodeToString(serializer, value)

    fun <T> decode(serializer: KSerializer<T>, text: String): T =
        json.decodeFromString(serializer, text)

    fun <T> encodeList(serializer: KSerializer<T>, values: List<T>): String =
        json.encodeToString(ListSerializer(serializer), values)

    fun <T> decodeList(serializer: KSerializer<T>, text: String?): List<T> =
        if (text.isNullOrBlank()) emptyList() else json.decodeFromString(ListSerializer(serializer), text)

    fun <T> decodeOptional(serializer: KSerializer<T>, text: String?): T? =
        if (text.isNullOrBlank()) null else json.decodeFromString(serializer, text)
}
