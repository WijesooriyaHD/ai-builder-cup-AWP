package com.aiwellnesspal.app

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundReceiver

/**
 * In-widget flip button for the Life-toolkit data widgets, mirroring the iOS
 * `arrow.2.squarepath` button. It swaps the default emoji + title tile for the
 * tool's live-data face.
 *
 * The tap fires the same Dart background callback iOS uses — `tool_flip` for
 * most tools, `hydration_flip` for Hydration — which toggles the
 * `flipped_<id>` key and reloads the widget, so no app launch is needed.
 */
object WidgetFlip {
    private const val ICON_LIGHT = 0xFF4A5568.toInt()
    private const val ICON_DARK = 0xFFE2E8F0.toInt()

    /** Shows the flip button on [views] and wires it to [uri]. */
    fun bind(context: Context, views: RemoteViews, uri: String, dark: Boolean?) {
        views.setViewVisibility(R.id.flip_toggle, View.VISIBLE)
        // While following the phone, the night-qualified drawable handles color.
        if (dark != null) {
            views.setInt(R.id.flip_toggle, "setColorFilter", if (dark) ICON_DARK else ICON_LIGHT)
        }
        val intent = Intent(context, HomeWidgetBackgroundReceiver::class.java).apply {
            action = "es.antonborri.home_widget.action.BACKGROUND"
            data = Uri.parse(uri)
        }
        val pi = PendingIntent.getBroadcast(
            context,
            uri.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.flip_toggle, pi)
    }

    /** Generic `tool_flip` binding used by every data widget except Hydration. */
    fun bindTool(context: Context, views: RemoteViews, widgetId: String, kind: String, dark: Boolean?) =
        bind(context, views, "aiwellnesspal://tool_flip?w=$widgetId&kind=$kind", dark)

    /**
     * Fills tool_data_widget with an empty state, so a flip always visibly
     * responds — even before the tool has any data (iOS does the same).
     */
    fun emptyFace(
        views: RemoteViews,
        emoji: String,
        title: String = "No data yet",
        subtitle: String = "Tap to open"
    ) {
        views.setTextViewText(R.id.data_value, emoji)
        views.setTextViewText(R.id.data_title, title)
        views.setTextViewText(R.id.data_subtitle, subtitle)
    }
}
