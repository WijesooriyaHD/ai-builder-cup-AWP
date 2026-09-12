package com.aiwellnesspal.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundReceiver
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * "Today's Habits" home-screen widget.
 *
 * Shows the day's active habits (up to 4) as tappable checkbox rows with a
 * progress indicator. Tapping a row toggles today's completion via the
 * home_widget background callback (no app launch).
 *
 * Keys written by HabitBuilderState._writeHabitWidgetData:
 *   habit_has_habits (bool), habit_count (int), habit_completed (int),
 *   habit_total (int), habit_progress (int),
 *   habit_{n}_id / _text / _emoji / _checked  (n = 1..4)
 */
class HabitWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.habit_widget).apply {
                val hasHabits = widgetData.getBoolean("habit_has_habits", false)

                val rowIds = intArrayOf(R.id.h_row1, R.id.h_row2, R.id.h_row3, R.id.h_row4)
                val checkIds = intArrayOf(R.id.h_row1_check, R.id.h_row2_check, R.id.h_row3_check, R.id.h_row4_check)
                val emojiIds = intArrayOf(R.id.h_row1_emoji, R.id.h_row2_emoji, R.id.h_row3_emoji, R.id.h_row4_emoji)
                val textIds = intArrayOf(R.id.h_row1_text, R.id.h_row2_text, R.id.h_row3_text, R.id.h_row4_text)

                if (!hasHabits) {
                    setViewVisibility(R.id.h_empty, View.VISIBLE)
                    for (id in rowIds) setViewVisibility(id, View.GONE)
                    setViewVisibility(R.id.h_progress_label, View.GONE)
                    setViewVisibility(R.id.h_progress_bar, View.GONE)
                } else {
                    setViewVisibility(R.id.h_empty, View.GONE)

                    val count = widgetData.getInt("habit_count", 0).coerceIn(0, 4)
                    val completed = widgetData.getInt("habit_completed", 0)
                    val total = widgetData.getInt("habit_total", 0)
                    val progress = widgetData.getInt("habit_progress", 0)

                    for (i in 0 until 4) {
                        val n = i + 1
                        if (i < count) {
                            val id = widgetData.getString("habit_${n}_id", "") ?: ""
                            val text = widgetData.getString("habit_${n}_text", "") ?: ""
                            val emoji = widgetData.getString("habit_${n}_emoji", "") ?: ""
                            val checked = widgetData.getBoolean("habit_${n}_checked", false)

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

                    setViewVisibility(R.id.h_progress_label, View.VISIBLE)
                    setViewVisibility(R.id.h_progress_bar, View.VISIBLE)
                    setTextViewText(R.id.h_progress_label, "$completed of $total done")
                    setProgressBar(R.id.h_progress_bar, 100, progress, false)
                }

                // Title/header click opens the app.
                val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                if (launchIntent != null) {
                    val pendingIntent = PendingIntent.getActivity(
                        context,
                        0,
                        launchIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    setOnClickPendingIntent(R.id.h_title, pendingIntent)
                    setOnClickPendingIntent(R.id.h_empty, pendingIntent)
                }
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
