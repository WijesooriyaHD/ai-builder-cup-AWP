package com.aiwellnesspal.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundReceiver
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
        MidnightWidgetRefresh.schedule(context)
        for (appWidgetId in appWidgetIds) {
            val flipped = widgetData.getBoolean("flipped_tool_meal_planner", false)
            val count = widgetData.getInt("meal_count", 0)
            var idx = widgetData.getInt("meal_index_tool_meal_planner", 0)
            if (count > 0) idx = ((idx % count) + count) % count else idx = 0
            val name = widgetData.getString("meal_${idx}_name", "") ?: ""
            val type = widgetData.getString("meal_${idx}_type", "") ?: ""
            val cal = widgetData.getInt("meal_${idx}_cal", 0)

            val hasLiveData = count > 0 && name.isNotEmpty()
            // Flipped always shows the data face (an empty state until there's
            // data), so the flip button visibly responds — as on iOS.
            val showingData = flipped
            val views = if (showingData && hasLiveData) {
                // Meal card + up/down arrows to browse today's meals (as on iOS).
                RemoteViews(context.packageName, R.layout.meal_planner_data_widget).apply {
                    setTextViewText(R.id.meal_type, type)
                    setTextViewText(R.id.meal_name, name)
                    setTextViewText(R.id.meal_cal, "$cal kcal")
                    setTextViewText(R.id.meal_position, "${idx + 1} / $count")
                    setInt(R.id.tool_root, "setBackgroundResource", R.drawable.tool_bg_meal_planner)
                    setOnClickPendingIntent(R.id.tool_root, launchIntent(context))
                    setOnClickPendingIntent(R.id.meal_prev, mealIndexIntent(context, -1))
                    setOnClickPendingIntent(R.id.meal_next, mealIndexIntent(context, 1))
                }
            } else if (showingData) {
                RemoteViews(context.packageName, R.layout.tool_data_widget).apply {
                    WidgetFlip.emptyFace(this, "🍽️", "No plan yet", "Open app to generate")
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
            // Per-widget light/dark theme (follows the phone until toggled).
            val dark = WidgetTheme.override(widgetData, "tool_meal_planner")
            WidgetTheme.background(views, R.id.tool_root, dark,
                R.drawable.tool_bg_meal_planner_light, R.drawable.tool_bg_meal_planner_dark)
            if (showingData && hasLiveData) {
                WidgetTheme.text(views, dark, R.id.meal_name, R.id.meal_cal, R.id.meal_position)
            } else if (showingData) {
                WidgetTheme.text(views, dark, R.id.data_value, R.id.data_title, R.id.data_subtitle)
            } else {
                WidgetTheme.text(views, dark, R.id.tool_label)
            }
            WidgetTheme.bindToggle(context, views, "tool_meal_planner", dark)
            WidgetFlip.bindTool(context, views, "tool_meal_planner", "MealPlannerToolWidget", dark)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    /** Fires the shared Dart callback that steps meal_index_<id> by [dir]. */
    private fun mealIndexIntent(context: Context, dir: Int): PendingIntent {
        val intent = Intent(context, HomeWidgetBackgroundReceiver::class.java).apply {
            action = "es.antonborri.home_widget.action.BACKGROUND"
            data = Uri.parse("aiwellnesspal://meal_index?w=tool_meal_planner&dir=$dir")
        }
        return PendingIntent.getBroadcast(
            context,
            "meal_index_$dir".hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun launchIntent(context: Context) = HomeWidgetLaunchIntent.getActivity(
        context,
        MainActivity::class.java,
        Uri.parse("aiwellnesspal://open?homeWidget=1&screen=tool_meal_planner")
    )
}
