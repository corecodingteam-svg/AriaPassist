package com.aria.pa

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Opens Aria at a deep link (aria:///talk, aria:///reminder/<id>, …). */
private fun open(context: Context, link: String) =
    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(link))

/** "Next reminder" widget — data written by lib/features/widgets/home_widgets.dart. */
class NextReminderWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_next).apply {
                setTextViewText(R.id.next_title, widgetData.getString("next_title", "Nothing coming up"))
                setTextViewText(R.id.next_time, widgetData.getString("next_time", "Tap the mic to add one"))
                setOnClickPendingIntent(R.id.widget_root, open(context, widgetData.getString("next_link", "aria:///today")!!))
                setOnClickPendingIntent(R.id.widget_mic, open(context, "aria:///talk"))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}

/** "Today" list widget (up to 3 upcoming items). */
class TodayWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_today).apply {
                setTextViewText(R.id.today_header, widgetData.getString("today_count", "Today"))
                setTextViewText(R.id.today_lines, widgetData.getString("today_lines", "A clear day"))
                setOnClickPendingIntent(R.id.widget_root, open(context, "aria:///today"))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}

/** One-tap "Talk to Aria" widget. */
class MicWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_mic).apply {
                setOnClickPendingIntent(R.id.widget_root, open(context, "aria:///talk"))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
