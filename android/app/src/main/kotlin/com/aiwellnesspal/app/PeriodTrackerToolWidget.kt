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
        MidnightWidgetRefresh.schedule(context)
        // Saved data adjusted for today (rolls over at midnight; see WidgetDay).
        val today = WidgetDay.period(widgetData)
        for (appWidgetId in appWidgetIds) {
            val flipped = today.getBoolean("flipped_tool_period_tracker", false)
            val hasData = today.getBoolean("period_has_data", false)
            val phase = today.getString("period_phase", "") ?: ""
            val emoji = today.getString("period_emoji", "🌸") ?: "🌸"
            val day = today.getInt("period_cycle_day", 0)
            val daysUntil = today.getInt("period_days_until_next", -999)

            // Flipped always shows the data face (an empty state until there's
            // data), so the flip button visibly responds — as on iOS.
            val showingData = flipped
            val views = if (showingData) {
                RemoteViews(context.packageName, R.layout.tool_data_widget).apply {
                    if (hasData) {
                        setTextViewText(R.id.data_value, emoji)
                        setTextViewText(R.id.data_title, "$phase · Day $day")
                        setTextViewText(R.id.data_subtitle, nextText(daysUntil))
                    } else {
                        WidgetFlip.emptyFace(this, "🌸")
                    }
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
            // Per-widget light/dark theme (follows the phone until toggled).
            val dark = WidgetTheme.override(widgetData, "tool_period_tracker")
            WidgetTheme.background(views, R.id.tool_root, dark,
                R.drawable.tool_bg_period_tracker_light, R.drawable.tool_bg_period_tracker_dark)
            if (showingData) {
                WidgetTheme.text(views, dark, R.id.data_value, R.id.data_title, R.id.data_subtitle)
            } else {
                WidgetTheme.text(views, dark, R.id.tool_label)
            }
            WidgetTheme.bindToggle(context, views, "tool_period_tracker", dark)
            WidgetFlip.bindTool(context, views, "tool_period_tracker", "PeriodTrackerToolWidget", dark)
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
