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
 * Wellness Intention home-screen widget.
 *
 * Shows the pinned intention's icon + title, its current active task (first
 * incomplete step) with a tappable checkbox, and a progress indicator — a
 * compact mirror of the in-app intention card. Tapping the active task toggles
 * it via the home_widget background callback (no app launch).
 *
 * Keys written by AppState._updateIntentionWidget / _syncIntentionWidgetInIsolate:
 *   intention_has_intention (bool), intention_id, intention_title,
 *   intention_task1_text/_id/_checked, intention_task2_text/_id/_checked,
 *   intention_next_task, intention_all_done (bool),
 *   intention_completed (int), intention_total (int), intention_progress (int).
 */
class IntentionWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences
    ) {
        MidnightWidgetRefresh.schedule(context)
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.intention_widget).apply {
                val hasIntention = widgetData.getBoolean("intention_has_intention", false)
                val title = widgetData.getString("intention_title", "Wellness Intention")
                val intentionId = widgetData.getString("intention_id", null)

                setTextViewText(R.id.widget_title, title)

                if (!hasIntention || intentionId.isNullOrEmpty()) {
                    // Empty state.
                    setViewVisibility(R.id.widget_empty, View.VISIBLE)
                    setViewVisibility(R.id.row1, View.GONE)
                    setViewVisibility(R.id.row2, View.GONE)
                    setViewVisibility(R.id.progress_container, View.GONE)
                } else {
                    setViewVisibility(R.id.widget_empty, View.GONE)

                    val allDone = widgetData.getBoolean("intention_all_done", false)
                    val completed = widgetData.getInt("intention_completed", 0)
                    val total = widgetData.getInt("intention_total", 0)
                    val progress = widgetData.getInt("intention_progress", 0)

                    if (allDone) {
                        // Celebration: single row, no tap.
                        setViewVisibility(R.id.row1, View.VISIBLE)
                        setViewVisibility(R.id.row2, View.GONE)
                        setTextViewText(R.id.row1_check, "\u2611")
                        setTextViewText(R.id.row1_text, "All steps complete \uD83C\uDF89")
                    } else {
                        // Row 1.
                        bindTaskRow(
                            context, this, intentionId,
                            rowId = R.id.row1, checkId = R.id.row1_check, textId = R.id.row1_text,
                            requestCode = 510,
                            text = widgetData.getString("intention_task1_text", "") ?: "",
                            taskId = widgetData.getString("intention_task1_id", "") ?: "",
                            checked = widgetData.getBoolean("intention_task1_checked", false)
                        )
                        // Row 2.
                        bindTaskRow(
                            context, this, intentionId,
                            rowId = R.id.row2, checkId = R.id.row2_check, textId = R.id.row2_text,
                            requestCode = 511,
                            text = widgetData.getString("intention_task2_text", "") ?: "",
                            taskId = widgetData.getString("intention_task2_id", "") ?: "",
                            checked = widgetData.getBoolean("intention_task2_checked", false)
                        )
                    }

                    // Progress section.
                    setViewVisibility(R.id.progress_container, View.VISIBLE)
                    setTextViewText(R.id.progress_label, "$completed of $total steps")
                    setProgressBar(R.id.progress_bar, 100, progress, false)
                }

                // Title/icon click opens the app on the Wellness Intentions tab.
                val launchPendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("aiwellnesspal://open?homeWidget=1&screen=intentions")
                )
                setOnClickPendingIntent(R.id.widget_title, launchPendingIntent)
                setOnClickPendingIntent(R.id.widget_empty, launchPendingIntent)
            }
            // Per-widget light/dark theme (follows the phone until toggled).
            val dark = WidgetTheme.override(widgetData, "intention")
            WidgetTheme.background(views, R.id.widget_root, dark,
                R.drawable.bg_wellness_intention_light, R.drawable.bg_wellness_intention_dark)
            for (chip in intArrayOf(R.id.widget_empty, R.id.row1, R.id.row2)) {
                WidgetTheme.background(views, chip, dark,
                    R.drawable.widget_chip_light, R.drawable.widget_chip_dark)
            }
            WidgetTheme.text(views, dark, R.id.widget_empty, R.id.row1_text, R.id.row2_text, R.id.progress_label)
            WidgetTheme.bindToggle(context, views, "intention", dark)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    /// Binds a single tappable task row. Hides the row when [text] is empty.
    private fun bindTaskRow(
        context: Context,
        views: RemoteViews,
        intentionId: String,
        rowId: Int,
        checkId: Int,
        textId: Int,
        requestCode: Int,
        text: String,
        taskId: String,
        checked: Boolean
    ) {
        if (text.isEmpty()) {
            views.setViewVisibility(rowId, View.GONE)
            return
        }
        views.setViewVisibility(rowId, View.VISIBLE)
        views.setTextViewText(checkId, if (checked) "\u2611" else "\u2610")

        if (checked) {
            val s = android.text.SpannableString(text)
            s.setSpan(
                android.text.style.StrikethroughSpan(),
                0, s.length,
                android.text.Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            views.setTextViewText(textId, s)
        } else {
            views.setTextViewText(textId, text)
        }

        if (taskId.isNotEmpty()) {
            val toggleIntent = Intent(context, HomeWidgetBackgroundReceiver::class.java).apply {
                action = "es.antonborri.home_widget.action.BACKGROUND"
                data = Uri.parse("aiwellnesspal://intention_toggle?id=$intentionId&task=$taskId")
            }
            val pi = PendingIntent.getBroadcast(
                context,
                requestCode,
                toggleIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(rowId, pi)
        }
    }
}
