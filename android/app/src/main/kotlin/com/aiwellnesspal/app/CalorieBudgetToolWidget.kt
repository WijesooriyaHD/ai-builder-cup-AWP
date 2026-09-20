package com.aiwellnesspal.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Life-toolkit widget for "Calorie Budget".
 *
 * Default → emoji + title tile. When flipped (flipped_tool_calorie_budget) with
 * data, shows kcal remaining + consumed/budget. Tapping opens the app at
 * aiwellnesspal://open?homeWidget=1&screen=tool_calorie_budget.
 */
class CalorieBudgetToolWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val flipped = widgetData.getBoolean("flipped_tool_calorie_budget", false)
            val budget = widgetData.getInt("calorie_budget", 0)
            val consumed = widgetData.getInt("calorie_consumed", 0)
            val remaining = widgetData.getInt("calorie_remaining", 0)

            val views = if (flipped && budget > 0) {
                RemoteViews(context.packageName, R.layout.tool_data_widget).apply {
                    setTextViewText(R.id.data_value, "$remaining")
                    setTextViewText(R.id.data_title, "kcal left")
                    setTextViewText(R.id.data_subtitle, "$consumed eaten · $budget budget")
                    setInt(R.id.tool_root, "setBackgroundResource", R.drawable.tool_bg_calorie_budget)
                    setOnClickPendingIntent(R.id.tool_root, launchIntent(context))
                }
            } else {
                RemoteViews(context.packageName, R.layout.tool_widget).apply {
                    setInt(R.id.tool_root, "setBackgroundResource", R.drawable.tool_bg_calorie_budget)
                    setTextViewText(R.id.tool_emoji, "🔥")
                    setTextViewText(R.id.tool_label, "Calorie Budget")
                    setOnClickPendingIntent(R.id.tool_root, launchIntent(context))
                }
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun launchIntent(context: Context) = HomeWidgetLaunchIntent.getActivity(
        context,
        MainActivity::class.java,
        Uri.parse("aiwellnesspal://open?homeWidget=1&screen=tool_calorie_budget")
    )
}
