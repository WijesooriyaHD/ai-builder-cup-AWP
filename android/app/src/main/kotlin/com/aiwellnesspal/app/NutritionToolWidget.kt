package com.aiwellnesspal.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Life-toolkit widget for "Nutrition Coach".
 *
 * Default → emoji + title tile. When flipped (flipped_tool_nutrition) and data
 * exists, shows today's calories vs goal + macros. Android RemoteViews cannot
 * host the iOS flip animation, so the flip state is read from shared prefs.
 * Tapping opens the app at aiwellnesspal://open?homeWidget=1&screen=tool_nutrition.
 */
class NutritionToolWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val flipped = widgetData.getBoolean("flipped_tool_nutrition", false)
            val goal = widgetData.getInt("nutrition_calorie_goal", 0)
            val calories = widgetData.getInt("nutrition_calories", 0)
            val protein = widgetData.getInt("nutrition_protein", 0)
            val carbs = widgetData.getInt("nutrition_carbs", 0)
            val fat = widgetData.getInt("nutrition_fat", 0)

            val views = if (flipped && goal > 0) {
                RemoteViews(context.packageName, R.layout.tool_data_widget).apply {
                    setTextViewText(R.id.data_value, "$calories")
                    setTextViewText(R.id.data_title, "/ $goal kcal")
                    setTextViewText(R.id.data_subtitle, "P${protein} C${carbs} F${fat}")
                    setInt(R.id.tool_root, "setBackgroundResource", R.drawable.tool_bg_nutrition)
                    setOnClickPendingIntent(R.id.tool_root, launchIntent(context))
                }
            } else {
                RemoteViews(context.packageName, R.layout.tool_widget).apply {
                    setInt(R.id.tool_root, "setBackgroundResource", R.drawable.tool_bg_nutrition)
                    setTextViewText(R.id.tool_emoji, "🥗")
                    setTextViewText(R.id.tool_label, "Nutrition Coach")
                    setOnClickPendingIntent(R.id.tool_root, launchIntent(context))
                }
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun launchIntent(context: Context) = HomeWidgetLaunchIntent.getActivity(
        context,
        MainActivity::class.java,
        Uri.parse("aiwellnesspal://open?homeWidget=1&screen=tool_nutrition")
    )
}
