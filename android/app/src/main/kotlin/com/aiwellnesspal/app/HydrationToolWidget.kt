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
 * a progress bar, and consumed / goal amounts. The flip button (top-left) swaps
 * between the default tile and this progress face, like iOS — RemoteViews can't
 * animate the 3D flip, so it's an instant swap. Tapping elsewhere opens the app
 * and deep-links to the tool via aiwellnesspal://open?homeWidget=1&screen=tool_hydration.
 */
class HydrationToolWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences
    ) {
        MidnightWidgetRefresh.schedule(context)
        // Saved data adjusted for today (rolls over at midnight; see WidgetDay).
        val today = WidgetDay.hydration(widgetData)
        for (appWidgetId in appWidgetIds) {
            val hasData = today.getBoolean("hydration_has_data", false)
            val flipped = today.getBoolean("hydration_flipped_tool_hydration", false)
            val pct = today.getInt("hydration_pct", 0)
            val consumed = today.getInt("hydration_consumed_ml", 0)
            val goal = today.getInt("hydration_goal_ml", 0)

            // Default → emoji + title tile (matches the other tool widgets and the
            // "Add Widget" gallery). Flipped → today's water progress. Like iOS,
            // the ring shows 0% of the app's default 2 L goal before any data has
            // synced, so the flip responds straight away on a fresh install.
            val showingData = flipped
            val goalMl = if (hasData && goal > 0) goal else 2000
            val pctShown = if (hasData) pct else 0
            val consumedShown = if (hasData) consumed else 0
            val views = if (showingData) {
                RemoteViews(context.packageName, R.layout.hydration_tool_widget).apply {
                    setTextViewText(R.id.hydration_pct, "$pctShown%")
                    setTextViewText(R.id.hydration_amount, "${mlText(consumedShown)} / ${mlText(goalMl)}")
                    setProgressBar(R.id.hydration_progress, 100, pctShown.coerceIn(0, 100), false)
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
            // Per-widget light/dark theme (follows the phone until toggled).
            val dark = WidgetTheme.override(widgetData, "tool_hydration")
            WidgetTheme.background(views, R.id.tool_root, dark,
                R.drawable.tool_bg_hydration_light, R.drawable.tool_bg_hydration_dark)
            if (showingData) {
                WidgetTheme.text(views, dark, R.id.hydration_pct, R.id.hydration_amount, R.id.hydration_label)
            } else {
                WidgetTheme.text(views, dark, R.id.tool_label)
            }
            WidgetTheme.bindToggle(context, views, "tool_hydration", dark)
            WidgetFlip.bind(context, views, "aiwellnesspal://hydration_flip?w=tool_hydration", dark)
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
