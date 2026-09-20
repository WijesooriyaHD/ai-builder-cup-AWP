package com.aiwellnesspal.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Life-toolkit widget for "Hydration Coach".
 *
 * Shows live hydration data written by the app into shared prefs
 * (see HydrationState.syncHydrationWidget in Dart): today's completion percent,
 * a progress bar, and consumed / goal amounts. Android home-screen widgets use
 * RemoteViews, which cannot host the iOS-style 3D flip animation, so this shows
 * the progress "front" face only. Tapping opens the app and deep-links to the
 * tool via aiwellnesspal://open?homeWidget=1&screen=tool_hydration.
 */
class HydrationToolWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val hasData = widgetData.getBoolean("hydration_has_data", false)
            val flipped = widgetData.getBoolean("hydration_flipped_tool_hydration", false)
            val pct = widgetData.getInt("hydration_pct", 0)
            val consumed = widgetData.getInt("hydration_consumed_ml", 0)
            val goal = widgetData.getInt("hydration_goal_ml", 0)

            // Default → emoji + title tile (matches the other tool widgets and the
            // "Add Widget" gallery). Flipped (with data) → today's water progress.
            val views = if (flipped && hasData) {
                RemoteViews(context.packageName, R.layout.hydration_tool_widget).apply {
                    setTextViewText(R.id.hydration_pct, "$pct%")
                    setTextViewText(R.id.hydration_amount, "${mlText(consumed)} / ${mlText(goal)}")
                    setProgressBar(R.id.hydration_progress, 100, pct.coerceIn(0, 100), false)
                    setTextViewText(R.id.hydration_label, "Hydration Coach")

                    setOnClickPendingIntent(R.id.tool_root, launchIntent(context))
                }
            } else {
                RemoteViews(context.packageName, R.layout.tool_widget).apply {
                    setInt(R.id.tool_root, "setBackgroundResource", R.drawable.tool_bg_hydration)
                    setTextViewText(R.id.tool_emoji, "💧")
                    setTextViewText(R.id.tool_label, "Hydration Coach")
                    setOnClickPendingIntent(R.id.tool_root, launchIntent(context))
                }
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun launchIntent(context: Context) = HomeWidgetLaunchIntent.getActivity(
        context,
        MainActivity::class.java,
        Uri.parse("aiwellnesspal://open?homeWidget=1&screen=tool_hydration")
    )

    private fun mlText(ml: Int): String =
        if (ml >= 1000) String.format("%.1fL", ml / 1000.0) else "${ml}ml"
}
