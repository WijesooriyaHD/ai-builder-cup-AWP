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
        MidnightWidgetRefresh.schedule(context)
        // Saved data adjusted for today (rolls over at midnight; see WidgetDay).
        val today = WidgetDay.calorieBudget(widgetData)
        for (appWidgetId in appWidgetIds) {
            val flipped = today.getBoolean("flipped_tool_calorie_budget", false)
            val budget = today.getInt("calorie_budget", 0)
            val consumed = today.getInt("calorie_consumed", 0)
            val remaining = today.getInt("calorie_remaining", 0)

            val hasLiveData = budget > 0
            // Flipped always shows the data face (an empty state until there's
            // data), so the flip button visibly responds — as on iOS.
            val showingData = flipped
            val views = if (showingData) {
                RemoteViews(context.packageName, R.layout.tool_data_widget).apply {
                    if (hasLiveData) {
                        setTextViewText(R.id.data_value, "$remaining")
                        setTextViewText(R.id.data_title, "kcal left")
                        setTextViewText(R.id.data_subtitle, "$consumed eaten · $budget budget")
                    } else {
                        WidgetFlip.emptyFace(this, "🔥")
                    }
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
            // Per-widget light/dark theme (follows the phone until toggled).
            val dark = WidgetTheme.override(widgetData, "tool_calorie_budget")
            WidgetTheme.background(views, R.id.tool_root, dark,
                R.drawable.tool_bg_calorie_budget_light, R.drawable.tool_bg_calorie_budget_dark)
            if (showingData) {
                WidgetTheme.text(views, dark, R.id.data_value, R.id.data_title, R.id.data_subtitle)
            } else {
                WidgetTheme.text(views, dark, R.id.tool_label)
            }
            WidgetTheme.bindToggle(context, views, "tool_calorie_budget", dark)
            WidgetFlip.bindTool(context, views, "tool_calorie_budget", "CalorieBudgetToolWidget", dark)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun launchIntent(context: Context) = HomeWidgetLaunchIntent.getActivity(
        context,
        MainActivity::class.java,
        Uri.parse("aiwellnesspal://open?homeWidget=1&screen=tool_calorie_budget")
    )
}
