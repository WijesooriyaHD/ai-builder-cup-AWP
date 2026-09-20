package com.aiwellnesspal.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Life-toolkit widget for "Meal Planner".
 *
 * Default → emoji + title tile. When flipped (flipped_tool_meal_planner) with a
 * plan, shows the current meal (name + type + calories). Android RemoteViews
 * cannot host the iOS arrow-scroll App Intents, so it shows the meal at the
 * synced index. Tapping opens the app at
 * aiwellnesspal://open?homeWidget=1&screen=tool_meal_planner.
 */
class MealPlannerToolWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val flipped = widgetData.getBoolean("flipped_tool_meal_planner", false)
            val count = widgetData.getInt("meal_count", 0)
            var idx = widgetData.getInt("meal_index_tool_meal_planner", 0)
            if (count > 0) idx = ((idx % count) + count) % count else idx = 0
            val name = widgetData.getString("meal_${idx}_name", "") ?: ""
            val type = widgetData.getString("meal_${idx}_type", "") ?: ""
            val cal = widgetData.getInt("meal_${idx}_cal", 0)

            val views = if (flipped && count > 0 && name.isNotEmpty()) {
                RemoteViews(context.packageName, R.layout.tool_data_widget).apply {
                    setTextViewText(R.id.data_value, type)
                    setTextViewText(R.id.data_title, name)
                    setTextViewText(R.id.data_subtitle, "$cal kcal · ${idx + 1}/$count")
                    setInt(R.id.tool_root, "setBackgroundResource", R.drawable.tool_bg_meal_planner)
                    setOnClickPendingIntent(R.id.tool_root, launchIntent(context))
                }
            } else {
                RemoteViews(context.packageName, R.layout.tool_widget).apply {
                    setInt(R.id.tool_root, "setBackgroundResource", R.drawable.tool_bg_meal_planner)
                    setTextViewText(R.id.tool_emoji, "🍽️")
                    setTextViewText(R.id.tool_label, "Meal Planner")
                    setOnClickPendingIntent(R.id.tool_root, launchIntent(context))
                }
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun launchIntent(context: Context) = HomeWidgetLaunchIntent.getActivity(
        context,
        MainActivity::class.java,
        Uri.parse("aiwellnesspal://open?homeWidget=1&screen=tool_meal_planner")
    )
}
