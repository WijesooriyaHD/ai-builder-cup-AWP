package com.aiwellnesspal.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundReceiver
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * "Today's Habits" home-screen widget.
 *
 * Shows the day's active habits (first two incomplete) as tappable checkbox
 * rows with a progress indicator, mirroring the Wellness Intention widget.
 * Tapping a row toggles today's completion via the home_widget background
 * callback (no app launch).
 *
 * Keys written by HabitBuilderState._writeHabitWidgetData:
 *   habit_has_habits (bool), habit_all_done (bool), habit_count (int),
 *   habit_completed (int), habit_total (int), habit_progress (int),
 *   habit_{n}_id / _text / _emoji / _checked  (n = 1..2)
 */
class HabitWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences
    ) {
        MidnightWidgetRefresh.schedule(context)
        // Saved data adjusted for today (rolls over at midnight; see WidgetDay).
        val today = WidgetDay.habits(widgetData)
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.habit_widget).apply {
                val hasHabits = today.getBoolean("habit_has_habits", false)

                // Only two rows are shown, matching the Wellness Intention widget.
                val rowIds = intArrayOf(R.id.h_row1, R.id.h_row2)
                val checkIds = intArrayOf(R.id.h_row1_check, R.id.h_row2_check)
                val emojiIds = intArrayOf(R.id.h_row1_emoji, R.id.h_row2_emoji)
                val textIds = intArrayOf(R.id.h_row1_text, R.id.h_row2_text)

                if (!hasHabits) {
                    setViewVisibility(R.id.h_empty, View.VISIBLE)
                    for (id in rowIds) setViewVisibility(id, View.GONE)
                    setViewVisibility(R.id.h_progress_container, View.GONE)
                } else {
                    setViewVisibility(R.id.h_empty, View.GONE)

                    val allDone = today.getBoolean("habit_all_done", false)
                    val count = today.getInt("habit_count", 0).coerceIn(0, 2)
                    val completed = today.getInt("habit_completed", 0)
                    val total = today.getInt("habit_total", 0)
                    val progress = today.getInt("habit_progress", 0)

                    if (allDone) {
                        // Celebration: single static row, no tap.
                        setViewVisibility(R.id.h_row1, View.VISIBLE)
                        setViewVisibility(R.id.h_row2, View.GONE)
                        setTextViewText(R.id.h_row1_check, "\u2611")
                        setTextViewText(R.id.h_row1_emoji, "")
                        setTextViewText(R.id.h_row1_text, "All habits done \uD83C\uDF89")
                    } else {
                    for (i in 0 until 2) {
                        val n = i + 1
                        if (i < count) {
                            val id = today.getString("habit_${n}_id", "") ?: ""
                            val text = today.getString("habit_${n}_text", "") ?: ""
                            val emoji = today.getString("habit_${n}_emoji", "") ?: ""
                            val checked = today.getBoolean("habit_${n}_checked", false)

                            setViewVisibility(rowIds[i], View.VISIBLE)
                            setTextViewText(checkIds[i], if (checked) "\u2611" else "\u2610")
                            setTextViewText(emojiIds[i], emoji)

                            if (checked) {
                                val s = android.text.SpannableString(text)
                                s.setSpan(
                                    android.text.style.StrikethroughSpan(),
                                    0, s.length,
                                    android.text.Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                                )
                                setTextViewText(textIds[i], s)
                            } else {
                                setTextViewText(textIds[i], text)
                            }

                            if (id.isNotEmpty()) {
                                val toggleIntent = Intent(context, HomeWidgetBackgroundReceiver::class.java).apply {
                                    action = "es.antonborri.home_widget.action.BACKGROUND"
                                    data = Uri.parse("aiwellnesspal://habit_toggle?id=$id")
                                }
                                val pi = PendingIntent.getBroadcast(
                                    context,
                                    600 + n, // Unique request code per row.
                                    toggleIntent,
                                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                                )
                                setOnClickPendingIntent(rowIds[i], pi)
                            }
                        } else {
                            setViewVisibility(rowIds[i], View.GONE)
                        }
                    }
                    }

                    setViewVisibility(R.id.h_progress_container, View.VISIBLE)
                    setTextViewText(R.id.h_progress_label, "$completed of $total done")
                    setProgressBar(R.id.h_progress_bar, 100, progress, false)
                }

                // Title/header click opens the app on the Habit Builder tab.
                // Uses home_widget's launch intent so the URI is delivered to
                // Dart via HomeWidget.initiallyLaunchedFromHomeWidget /
                // widgetClicked, which MainWrapper routes to the right tab.
                val launchPendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("aiwellnesspal://open?homeWidget=1&screen=habit_builder")
                )
                setOnClickPendingIntent(R.id.h_title, launchPendingIntent)
                setOnClickPendingIntent(R.id.h_empty, launchPendingIntent)
            }
            // Per-widget light/dark theme (follows the phone until toggled).
            val dark = WidgetTheme.override(widgetData, "habit")
            WidgetTheme.background(views, R.id.widget_root, dark,
                R.drawable.bg_todays_habits_light, R.drawable.bg_todays_habits_dark)
            for (chip in intArrayOf(R.id.h_empty, R.id.h_row1, R.id.h_row2)) {
                WidgetTheme.background(views, chip, dark,
                    R.drawable.widget_chip_light, R.drawable.widget_chip_dark)
            }
            WidgetTheme.text(views, dark, R.id.h_empty, R.id.h_row1_text, R.id.h_row2_text, R.id.h_progress_label)
            WidgetTheme.bindToggle(context, views, "habit", dark)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
