package com.aiwellnesspal.app

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.Color
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundReceiver

/**
 * Per-widget light/dark theme, mirroring the iOS in-widget sun/moon toggle.
 *
 * A widget follows the phone's dark mode until the user taps its toggle. While
 * following, nothing is overridden: the layouts' night-qualified resources
 * (drawable-night, values-night) apply, so the widget switches the moment the
 * phone does. Once toggled, `widget_theme_dark_<themeId>` is set and the widget
 * is pinned to the explicit `_light` / `_dark` resources below.
 *
 * The toggle fires the shared Dart background callback with the *target*
 * theme (`widget_theme_toggle?w=<id>&dark=<bool>`): Dart can't see the phone's
 * mode, so a plain flip of an unset (= light) value would do nothing on a dark
 * phone. iOS sends no `dark` param and keeps its plain flip.
 */
object WidgetTheme {
    private const val TEXT_LIGHT = 0xFF333333.toInt()
    private const val TEXT_DARK = Color.WHITE

    private fun key(themeId: String) = "widget_theme_dark_$themeId"

    /** The pinned theme, or null while the widget follows the phone. */
    fun override(prefs: SharedPreferences, themeId: String): Boolean? =
        if (prefs.contains(key(themeId))) prefs.getBoolean(key(themeId), false) else null

    private fun phoneIsDark(context: Context): Boolean =
        (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES

    /** Shows the right icon on the toggle and wires it to switch theme. */
    fun bindToggle(context: Context, views: RemoteViews, themeId: String, dark: Boolean?) {
        if (dark != null) {
            views.setImageViewResource(
                R.id.theme_toggle,
                if (dark) R.drawable.ic_theme_sun else R.drawable.ic_theme_moon
            )
        }
        val target = !(dark ?: phoneIsDark(context))
        val intent = Intent(context, HomeWidgetBackgroundReceiver::class.java).apply {
            action = "es.antonborri.home_widget.action.BACKGROUND"
            data = Uri.parse("aiwellnesspal://widget_theme_toggle?w=$themeId&dark=$target")
        }
        val pi = PendingIntent.getBroadcast(
            context,
            themeId.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.theme_toggle, pi)
    }

    /** Sets text colors for a pinned theme; no-op while following the phone. */
    fun text(views: RemoteViews, dark: Boolean?, vararg viewIds: Int) {
        if (dark == null) return
        val color = if (dark) TEXT_DARK else TEXT_LIGHT
        for (id in viewIds) views.setTextColor(id, color)
    }

    /**
     * Sets [viewId]'s background: [auto] (night-qualified) while following the
     * phone — skipped when null, leaving the layout's own background — else
     * the explicit [light] / [darkRes] drawable.
     */
    fun background(
        views: RemoteViews,
        viewId: Int,
        dark: Boolean?,
        light: Int,
        darkRes: Int,
        auto: Int? = null
    ) {
        val res = when (dark) {
            null -> auto ?: return
            true -> darkRes
            false -> light
        }
        views.setInt(viewId, "setBackgroundResource", res)
    }
}
