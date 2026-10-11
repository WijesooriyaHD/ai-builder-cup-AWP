package com.aiwellnesspal.app

import android.content.SharedPreferences
import org.json.JSONArray
import java.time.LocalDate
import java.time.temporal.ChronoUnit

/**
 * Makes widget data correct for *today* even when the app hasn't run since
 * midnight. The app stamps each date-scoped snapshot with the day it was
 * written (`<tool>_date`, yyyy-MM-dd). When a widget renders on a later day,
 * [view] overlays what the app itself would show for the new day:
 *
 *  - Hydration / Nutrition / Calorie Budget: today's totals reset to 0.
 *  - Period Tracker: cycle day, phase and days-until recomputed from the last
 *    logged start (a port of PeriodData in lib/models/period_data.dart).
 *  - Today's Plan: yesterday's plan → "open the app for today's plan".
 *  - Today's Habits: today's scheduled habits, all unchecked.
 *
 * A snapshot with no date stamp (written by an older app build) is shown as-is.
 * [MidnightWidgetRefresh] re-renders every widget just after midnight.
 */
object WidgetDay {
    fun today(): LocalDate = LocalDate.now()

    /** True when [dateKey] holds a date before today. */
    private fun isStale(prefs: SharedPreferences, dateKey: String): Boolean {
        val stamp = prefs.getString(dateKey, null) ?: return false
        return parse(stamp)?.isBefore(today()) ?: false
    }

    private fun parse(s: String): LocalDate? =
        try { if (s.isBlank()) null else LocalDate.parse(s) } catch (_: Exception) { null }

    /** Read-through view of the widget prefs with today's overrides applied. */
    class View(private val base: SharedPreferences, private val over: Map<String, Any?>) {
        fun getBoolean(key: String, def: Boolean): Boolean =
            if (over.containsKey(key)) over[key] as? Boolean ?: def else base.getBoolean(key, def)

        fun getInt(key: String, def: Int): Int =
            if (over.containsKey(key)) over[key] as? Int ?: def else base.getInt(key, def)

        fun getString(key: String, def: String?): String? =
            if (over.containsKey(key)) over[key] as? String ?: def else base.getString(key, def)
    }

    fun hydration(p: SharedPreferences) = View(p,
        if (isStale(p, "hydration_date"))
            mapOf("hydration_consumed_ml" to 0, "hydration_pct" to 0)
        else emptyMap())

    fun nutrition(p: SharedPreferences) = View(p,
        if (isStale(p, "nutrition_date"))
            mapOf("nutrition_calories" to 0, "nutrition_pct" to 0, "nutrition_protein" to 0,
                "nutrition_carbs" to 0, "nutrition_fat" to 0, "nutrition_meal_count" to 0)
        else emptyMap())

    fun calorieBudget(p: SharedPreferences) = View(p,
        if (isStale(p, "calorie_date"))
            mapOf("calorie_consumed" to 0, "calorie_burned" to 0, "calorie_pct" to 0,
                "calorie_remaining" to p.getInt("calorie_budget", 0))
        else emptyMap())

    fun plan(p: SharedPreferences) = View(p,
        if (isStale(p, "wellness_plan_date")) mapOf("wellness_placeholder" to true)
        else emptyMap())

    /** Period values for today, mirroring PeriodData's getters exactly. */
    fun period(p: SharedPreferences): View {
        val last = parse(p.getString("period_last_start", "") ?: "") ?: return View(p, emptyMap())
        val len = p.getInt("period_cycle_length", 28).coerceAtLeast(1)
        val periodLength = p.getInt("period_length", 5)
        val today = today()
        val diff = ChronoUnit.DAYS.between(last, today)
        val day = Math.floorMod(diff, len.toLong()).toInt() + 1
        val daysUntil = ChronoUnit.DAYS.between(today, last.plusDays(len.toLong())).toInt()
        val ovDay = len - 14
        val (label, emoji) = when {
            day <= periodLength -> "Menstrual" to "🌸"
            Math.abs(day - ovDay) <= 1 -> "Ovulation" to "🌼"
            day < ovDay -> "Follicular" to "🌱"
            else -> "Luteal" to "🌙"
        }
        return View(p, mapOf(
            "period_has_data" to true,
            "period_cycle_day" to day,
            "period_days_until_next" to daysUntil,
            "period_phase" to label,
            "period_emoji" to emoji,
        ))
    }

    /**
     * On a new day: today's scheduled habits (from `habit_schedule_json`),
     * none completed — the same rows the app writes (first two, max).
     */
    fun habits(p: SharedPreferences): View {
        if (!isStale(p, "habit_date")) return View(p, emptyMap())
        val json = p.getString("habit_schedule_json", null) ?: return View(p, emptyMap())
        val weekday = today().dayOfWeek.value // Mon=1..Sun=7, same as Dart.
        val scheduled = mutableListOf<Triple<String, String, String>>()
        try {
            val arr = JSONArray(json)
            for (i in 0 until arr.length()) {
                val h = arr.getJSONObject(i)
                val days = h.optJSONArray("days")
                val onToday = when (h.optString("freq")) {
                    "daily" -> true
                    "weekdays" -> weekday <= 5
                    "weekends" -> weekday >= 6
                    "custom" -> days != null && (0 until days.length()).any { days.optInt(it) == weekday }
                    else -> false
                }
                if (onToday) scheduled += Triple(h.optString("id"), h.optString("title"), h.optString("emoji", "⭐"))
            }
        } catch (_: Exception) {
            return View(p, emptyMap())
        }
        val over = mutableMapOf<String, Any?>(
            "habit_has_habits" to scheduled.isNotEmpty(),
            "habit_all_done" to false,
            "habit_count" to minOf(2, scheduled.size),
            "habit_completed" to 0,
            "habit_total" to scheduled.size,
            "habit_progress" to 0,
        )
        for (i in 0 until 2) {
            val n = i + 1
            val h = scheduled.getOrNull(i)
            over["habit_${n}_id"] = h?.first ?: ""
            over["habit_${n}_text"] = h?.second ?: ""
            over["habit_${n}_emoji"] = h?.third ?: ""
            over["habit_${n}_checked"] = false
        }
        return View(p, over)
    }
}
