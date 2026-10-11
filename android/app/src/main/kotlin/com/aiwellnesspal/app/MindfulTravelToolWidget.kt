package com.aiwellnesspal.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Life-toolkit shortcut widget for "Mindful Travel".
 *
 * A small square tile showing the tool emoji + label. Tapping it opens the app
 * and deep-links to the tool via home_widget's launch intent, handled in
 * Dart (MainWrapper._handleWidgetUri) at
 * aiwellnesspal://open?homeWidget=1&screen=tool_mindful_travel.
 */
class MindfulTravelToolWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences
    ) {
        MidnightWidgetRefresh.schedule(context)
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.tool_widget).apply {
                setInt(R.id.tool_root, "setBackgroundResource", R.drawable.tool_bg_mindful_travel)
                setTextViewText(R.id.tool_emoji, "✈️")
                setTextViewText(R.id.tool_label, "Mindful Travel")

                val launchPendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("aiwellnesspal://open?homeWidget=1&screen=tool_mindful_travel")
                )
                setOnClickPendingIntent(R.id.tool_root, launchPendingIntent)
            }
            // Per-widget light/dark theme (follows the phone until toggled).
            val dark = WidgetTheme.override(widgetData, "tool_mindful_travel")
            WidgetTheme.background(views, R.id.tool_root, dark,
                R.drawable.tool_bg_mindful_travel_light, R.drawable.tool_bg_mindful_travel_dark)
            WidgetTheme.text(views, dark, R.id.tool_label)
            WidgetTheme.bindToggle(context, views, "tool_mindful_travel", dark)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
