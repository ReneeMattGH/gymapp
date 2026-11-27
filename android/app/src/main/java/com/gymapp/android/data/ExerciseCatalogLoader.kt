package com.gymapp.android.data

import android.content.Context
import com.gymapp.android.domain.Exercise
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

object ExerciseCatalogLoader {
    val json: Json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
        explicitNulls = false
        isLenient = true
    }

    fun parse(text: String): List<Exercise> =
        json.decodeFromString(ListSerializer(Exercise.serializer()), text)

    fun load(context: Context): List<Exercise> =
        context.assets.open("exercises.json").bufferedReader().use { parse(it.readText()) }
}
