package com.aiwellnesspal.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Life-toolkit widget for "Body Weight".
 *
 * Default → emoji + title tile. When flipped (flipped_tool_weight_tracker) with
 * data, shows the current weight + unit + net change. Tapping opens the app at
 * aiwellnesspal://open?homeWidget=1&screen=tool_weight_tracker.
 */
class WeightTrackerToolWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val flipped = widgetData.getBoolean("flipped_tool_weight_tracker", false)
            val hasData = widgetData.getBoolean("weight_has_data", false)
            val current = widgetData.getString("weight_current", "") ?: ""
            val unit = widgetData.getString("weight_unit", "kg") ?: "kg"
            val change = widgetData.getString("weight_change", "") ?: ""

            val views = if (flipped && hasData && current.isNotEmpty()) {
                RemoteViews(context.packageName, R.layout.tool_data_widget).apply {
                    setTextViewText(R.id.data_value, "$current $unit")
                    setTextViewText(R.id.data_title, "Current weight")
                    setTextViewText(R.id.data_subtitle, if (change.isEmpty()) "" else "$change $unit")
                    setInt(R.id.tool_root, "setBackgroundResource", R.drawable.tool_bg_weight_tracker)
                    setOnClickPendingIntent(R.id.tool_root, launchIntent(context))
                }
            } else {
                RemoteViews(context.packageName, R.layout.tool_widget).apply {
                    setInt(R.id.tool_root, "setBackgroundResource", R.drawable.tool_bg_weight_tracker)
                    setTextViewText(R.id.tool_emoji, "⚖️")
                    setTextViewText(R.id.tool_label, "Body Weight")
                    setOnClickPendingIntent(R.id.tool_root, launchIntent(context))
                }
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun launchIntent(context: Context) = HomeWidgetLaunchIntent.getActivity(
        context,
        MainActivity::class.java,
        Uri.parse("aiwellnesspal://open?homeWidget=1&screen=tool_weight_tracker")
    )
}
