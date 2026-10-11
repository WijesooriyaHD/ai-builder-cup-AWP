package com.aiwellnesspal.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import java.time.LocalDate
import java.time.ZoneId

/**
 * Re-renders every home-screen widget just after local midnight so date-scoped
 * values roll over without the app being opened (see [WidgetDay]).
 *
 * Uses an inexact, non-wakeup alarm: if the phone is asleep at midnight the
 * refresh lands as soon as it wakes — before anyone can look at the widgets —
 * and no exact-alarm permission is needed. Also refreshes on clock/timezone
 * changes, boot and app updates, re-arming the next midnight each time.
 */
class MidnightWidgetRefresh : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        refreshAll(context)
        schedule(context)
    }

    companion object {
        private const val ACTION_MIDNIGHT = "com.aiwellnesspal.app.WIDGET_MIDNIGHT"

        private val PROVIDERS = listOf(
            AIWellnessWidget::class.java, HabitWidget::class.java, IntentionWidget::class.java,
            HydrationToolWidget::class.java, NutritionToolWidget::class.java,
            CalorieBudgetToolWidget::class.java, MealPlannerToolWidget::class.java,
            PeriodTrackerToolWidget::class.java, WeightTrackerToolWidget::class.java,
            SleepToolWidget::class.java, MeditationToolWidget::class.java,
            MindfulTravelToolWidget::class.java,
        )

        /** Arms (or re-arms) the alarm for 30s past the next local midnight. */
        fun schedule(context: Context) {
            val am = context.getSystemService(AlarmManager::class.java) ?: return
            val zone = ZoneId.systemDefault()
            val at = LocalDate.now(zone).plusDays(1).atStartOfDay(zone)
                .toInstant().toEpochMilli() + 30_000
            // Same request code + intent each time, so this replaces any earlier alarm.
            am.setAndAllowWhileIdle(AlarmManager.RTC, at, pendingIntent(context))
        }

        private fun pendingIntent(context: Context): PendingIntent =
            PendingIntent.getBroadcast(
                context, 7100,
                Intent(context, MidnightWidgetRefresh::class.java).setAction(ACTION_MIDNIGHT),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

        /** Asks every placed widget to re-render from its saved data. */
        fun refreshAll(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            for (cls in PROVIDERS) {
                val ids = mgr.getAppWidgetIds(ComponentName(context, cls))
                if (ids.isEmpty()) continue
                context.sendBroadcast(
                    Intent(context, cls)
                        .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                        .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                )
            }
        }
    }
}
