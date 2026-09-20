package com.aiwellnesspal.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Life-toolkit widget for "Period Tracker".
 *
 * Default → emoji + title tile. When flipped (flipped_tool_period_tracker) with
 * data, shows the current cycle phase + day + days-until-next. Tapping opens the
 * app at aiwellnesspal://open?homeWidget=1&screen=tool_period_tracker.
 */
class PeriodTrackerToolWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val flipped = widgetData.getBoolean("flipped_tool_period_tracker", false)
            val hasData = widgetData.getBoolean("period_has_data", false)
            val phase = widgetData.getString("period_phase", "") ?: ""
            val emoji = widgetData.getString("period_emoji", "🌸") ?: "🌸"
            val day = widgetData.getInt("period_cycle_day", 0)
            val daysUntil = widgetData.getInt("period_days_until_next", -999)

            val views = if (flipped && hasData) {
                RemoteViews(context.packageName, R.layout.tool_data_widget).apply {
                    setTextViewText(R.id.data_value, emoji)
                    setTextViewText(R.id.data_title, "$phase · Day $day")
                    setTextViewText(R.id.data_subtitle, nextText(daysUntil))
                    setInt(R.id.tool_root, "setBackgroundResource", R.drawable.tool_bg_period_tracker)
                    setOnClickPendingIntent(R.id.tool_root, launchIntent(context))
                }
            } else {
                RemoteViews(context.packageName, R.layout.tool_widget).apply {
                    setInt(R.id.tool_root, "setBackgroundResource", R.drawable.tool_bg_period_tracker)
                    setTextViewText(R.id.tool_emoji, "🌸")
                    setTextViewText(R.id.tool_label, "Period Tracker")
                    setOnClickPendingIntent(R.id.tool_root, launchIntent(context))
                }
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun nextText(days: Int): String = when {
        days == -999 -> ""
        days < 0 -> "${-days}d late"
        days == 0 -> "Due today"
        else -> "Next in ${days}d"
    }

    private fun launchIntent(context: Context) = HomeWidgetLaunchIntent.getActivity(
        context,
        MainActivity::class.java,
        Uri.parse("aiwellnesspal://open?homeWidget=1&screen=tool_period_tracker")
    )
}
