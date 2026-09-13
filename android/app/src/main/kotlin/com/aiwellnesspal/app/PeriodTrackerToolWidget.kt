package com.aiwellnesspal.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Life-toolkit shortcut widget for "Period Tracker".
 *
 * A small square tile showing the tool emoji + label. Tapping it opens the app
 * and deep-links to the tool via home_widget's launch intent, handled in
 * Dart (MainWrapper._handleWidgetUri) at
 * aiwellnesspal://open?homeWidget=1&screen=tool_period_tracker.
 */
class PeriodTrackerToolWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.tool_widget).apply {
                setTextViewText(R.id.tool_emoji, "🌸")
                setTextViewText(R.id.tool_label, "Period Tracker")

                val launchPendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("aiwellnesspal://open?homeWidget=1&screen=tool_period_tracker")
                )
                setOnClickPendingIntent(R.id.tool_root, launchPendingIntent)
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
