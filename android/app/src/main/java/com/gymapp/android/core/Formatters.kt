package com.gymapp.android.core

import com.gymapp.android.domain.UnitSystem
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.temporal.WeekFields
import java.util.Locale

object FormaDate {
    fun parse(value: String): Long? {
        val cleaned = value.trim()
        if (cleaned.isEmpty()) return null
        return runCatching { Instant.parse(cleaned).toEpochMilli() }
            .recoverCatching {
                Instant.parse(cleaned.replace(" ", "T")).toEpochMilli()
            }
            .recoverCatching {
                val offset = java.time.OffsetDateTime.parse(cleaned)
                offset.toInstant().toEpochMilli()
            }
            .getOrNull()
    }

    fun string(epochMillis: Long): String = Instant.ofEpochMilli(epochMillis).toString()

    fun date(epochMillis: Long): LocalDate =
        Instant.ofEpochMilli(epochMillis).atZone(ZoneId.systemDefault()).toLocalDate()

    fun localDateTime(epochMillis: Long): LocalDateTime =
        Instant.ofEpochMilli(epochMillis).atZone(ZoneId.systemDefault()).toLocalDateTime()

    fun epoch(date: LocalDate): Long =
        date.atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()

    fun isoWeekday(date: LocalDate): Int = date.dayOfWeek.value

    fun isoWeekday(epochMillis: Long): Int = isoWeekday(date(epochMillis))

    fun startOfWeek(date: LocalDate): LocalDate {
        val firstDay = WeekFields.of(Locale.getDefault()).firstDayOfWeek
        val current = date.dayOfWeek
        val diff = (current.value - firstDay.value + 7) % 7
        return date.minusDays(diff.toLong())
    }
}

object Formatters {
    fun clock(seconds: Int): String {
        val safe = maxOf(0, seconds)
        val hours = safe / 3600
        val minutes = (safe % 3600) / 60
        val secs = safe % 60
        return if (hours > 0) String.format(Locale.US, "%d:%02d:%02d", hours, minutes, secs)
        else String.format(Locale.US, "%02d:%02d", minutes, secs)
    }

    fun minutesLabel(seconds: Int): String {
        val minutes = Math.round(seconds / 60.0).toInt()
        if (minutes < 60) return "$minutes min"
        val hours = minutes / 60
        val rest = minutes % 60
        return if (rest == 0) "$hours hr" else "$hours hr $rest min"
    }

    fun duration(minutes: Int): String {
        if (minutes < 60) return "$minutes min"
        val hours = minutes / 60
        val rest = minutes % 60
        return if (rest == 0) "$hours hr" else "$hours hr $rest min"
    }

    fun longDate(date: LocalDate): String =
        date.format(DateTimeFormatter.ofPattern("EEEE, d MMMM", Locale.getDefault()))

    fun shortDate(date: LocalDate): String =
        date.format(DateTimeFormatter.ofPattern("d MMM", Locale.getDefault()))

    fun time(epochMillis: Long): String =
        FormaDate.localDateTime(epochMillis)
            .format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT))

    fun greeting(hour: Int = LocalDateTime.now().hour): String = when {
        hour < 5 -> "Late session"
        hour < 12 -> "Good morning"
        hour < 17 -> "Good afternoon"
        else -> "Good evening"
    }

    fun timeOfDay(value: String): String {
        val parts = value.split(":")
        if (parts.size != 2) return value
        val hour = parts[0].toIntOrNull() ?: return value
        val minute = parts[1].toIntOrNull() ?: return value
        val suffix = if (hour >= 12) "PM" else "AM"
        val display = if (hour % 12 == 0) 12 else hour % 12
        return "$display:${String.format(Locale.US, "%02d", minute)} $suffix"
    }

    fun hourMinute(value: String): Pair<Int, Int> {
        val parts = value.split(":")
        if (parts.size != 2) return 18 to 0
        val hour = parts[0].toIntOrNull() ?: 18
        val minute = parts[1].toIntOrNull() ?: 0
        return hour.coerceIn(0, 23) to minute.coerceIn(0, 59)
    }

    private val fullWeekdays = listOf(
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
    )

    fun weekdayFull(weekday: Int): String =
        if (weekday in 1..7) fullWeekdays[weekday - 1] else "—"

    fun weight(kilograms: Double, units: UnitSystem): String {
        if (units == UnitSystem.KG) {
            val rounded = Math.round(kilograms * 10) / 10.0
            return if (rounded == Math.floor(rounded)) "${rounded.toInt()} kg"
            else String.format(Locale.US, "%.1f kg", rounded)
        }
        val pounds = kilograms * 2.2046226218
        val rounded = Math.round(pounds * 10) / 10.0
        return if (rounded == Math.floor(rounded)) "${rounded.toInt()} lb"
        else String.format(Locale.US, "%.1f lb", rounded)
    }

    fun bodyWeight(kilograms: Double?, units: UnitSystem): String {
        if (kilograms == null || kilograms <= 0) return "—"
        return weight(kilograms, units)
    }
}
