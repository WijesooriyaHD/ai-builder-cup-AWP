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
        MidnightWidgetRefresh.schedule(context)
        // Saved data adjusted for today (rolls over at midnight; see WidgetDay).
        val today = WidgetDay.nutrition(widgetData)
        for (appWidgetId in appWidgetIds) {
            val flipped = today.getBoolean("flipped_tool_nutrition", false)
            val goal = today.getInt("nutrition_calorie_goal", 0)
            val calories = today.getInt("nutrition_calories", 0)
            val protein = today.getInt("nutrition_protein", 0)
            val carbs = today.getInt("nutrition_carbs", 0)
            val fat = today.getInt("nutrition_fat", 0)

            val hasLiveData = goal > 0
            // Flipped always shows the data face (an empty state until there's
            // data), so the flip button visibly responds — as on iOS.
            val showingData = flipped
            val views = if (showingData) {
                RemoteViews(context.packageName, R.layout.tool_data_widget).apply {
                    if (hasLiveData) {
                        setTextViewText(R.id.data_value, "$calories")
                        setTextViewText(R.id.data_title, "/ $goal kcal")
                        setTextViewText(R.id.data_subtitle, "P${protein} C${carbs} F${fat}")
                    } else {
                        WidgetFlip.emptyFace(this, "🥗")
                    }
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
            // Per-widget light/dark theme (follows the phone until toggled).
            val dark = WidgetTheme.override(widgetData, "tool_nutrition")
            WidgetTheme.background(views, R.id.tool_root, dark,
                R.drawable.tool_bg_nutrition_light, R.drawable.tool_bg_nutrition_dark)
            if (showingData) {
                WidgetTheme.text(views, dark, R.id.data_value, R.id.data_title, R.id.data_subtitle)
            } else {
                WidgetTheme.text(views, dark, R.id.tool_label)
            }
            WidgetTheme.bindToggle(context, views, "tool_nutrition", dark)
            WidgetFlip.bindTool(context, views, "tool_nutrition", "NutritionToolWidget", dark)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun launchIntent(context: Context) = HomeWidgetLaunchIntent.getActivity(
        context,
        MainActivity::class.java,
        Uri.parse("aiwellnesspal://open?homeWidget=1&screen=tool_nutrition")
    )
}
