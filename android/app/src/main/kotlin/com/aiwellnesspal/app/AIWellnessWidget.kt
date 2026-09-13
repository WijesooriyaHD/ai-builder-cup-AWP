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
 * AI Wellness (Today's Plan) home-screen widget.
 *
 * Shows the day's focus + icon, the first two incomplete actions as tappable
 * checkbox rows, an "Up next" preview of the following action, and a progress
 * indicator — matching the Wellness Intention widget. Tapping a row toggles the
 * action via the home_widget background callback (no app launch).
 *
 * Keys written by AppState.pushPlanToWidget / _syncWellnessWidgetInIsolate:
 *   wellness_placeholder (bool), wellness_focus, wellness_plan_id,
 *   wellness_task1_text/_id/_checked, wellness_task2_text/_id/_checked,
 *   wellness_next_task, wellness_all_done (bool),
 *   wellness_completed (int), wellness_total (int), wellness_progress (int).
 */
class AIWellnessWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.ai_wellness_widget).apply {
                val isPlaceholder = widgetData.getBoolean("wellness_placeholder", true)
                val planId = widgetData.getString("wellness_plan_id", null)

                val focus = widgetData.getString("wellness_focus", "Today's Focus") ?: "Today's Focus"
                setTextViewText(R.id.wellness_focus_label, focus)

                if (isPlaceholder) {
                    setViewVisibility(R.id.placeholder_message, View.VISIBLE)
                    setViewVisibility(R.id.w_row1, View.GONE)
                    setViewVisibility(R.id.w_row2, View.GONE)
                    setViewVisibility(R.id.w_progress_container, View.GONE)
                    setTextViewText(R.id.wellness_focus_label, "Today's Plan")
                } else {
                    setViewVisibility(R.id.placeholder_message, View.GONE)

                    val allDone = widgetData.getBoolean("wellness_all_done", false)
                    val completed = widgetData.getInt("wellness_completed", 0)
                    val total = widgetData.getInt("wellness_total", 0)
                    val progress = widgetData.getInt("wellness_progress", 0)

                    if (allDone) {
                        setViewVisibility(R.id.w_row1, View.VISIBLE)
                        setViewVisibility(R.id.w_row2, View.GONE)
                        setTextViewText(R.id.w_row1_check, "\u2611")
                        setTextViewText(R.id.w_row1_text, "All actions complete \uD83C\uDF89")
                    } else {
                        bindTaskRow(
                            context, this, planId,
                            rowId = R.id.w_row1, checkId = R.id.w_row1_check, textId = R.id.w_row1_text,
                            requestCode = 320,
                            text = widgetData.getString("wellness_task1_text", "") ?: "",
                            taskId = widgetData.getString("wellness_task1_id", "") ?: "",
                            checked = widgetData.getBoolean("wellness_task1_checked", false)
                        )
                        bindTaskRow(
                            context, this, planId,
                            rowId = R.id.w_row2, checkId = R.id.w_row2_check, textId = R.id.w_row2_text,
                            requestCode = 321,
                            text = widgetData.getString("wellness_task2_text", "") ?: "",
                            taskId = widgetData.getString("wellness_task2_id", "") ?: "",
                            checked = widgetData.getBoolean("wellness_task2_checked", false)
                        )
                    }

                    setViewVisibility(R.id.w_progress_container, View.VISIBLE)
                    setTextViewText(R.id.w_progress_label, "$completed of $total actions")
                    setProgressBar(R.id.w_progress_bar, 100, progress, false)
                }

                // Header click opens the app on the Home (daily plan) tab.
                val launchPendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("aiwellnesspal://open?homeWidget=1&screen=home")
                )
                setOnClickPendingIntent(R.id.wellness_focus_label, launchPendingIntent)
                setOnClickPendingIntent(R.id.placeholder_message, launchPendingIntent)
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    /// Binds a single tappable action row. Hides the row when [text] is empty.
    private fun bindTaskRow(
        context: Context,
        views: RemoteViews,
        planId: String?,
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
                data = Uri.parse("aiwellnesspal://wellness_toggle?plan_id=${planId ?: ""}&action_id=$taskId")
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
