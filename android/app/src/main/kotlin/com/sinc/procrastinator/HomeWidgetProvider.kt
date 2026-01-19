package com.sinc.procrastinator

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import android.net.Uri
import es.antonborri.home_widget.HomeWidgetProvider
import es.antonborri.home_widget.HomeWidgetLaunchIntent

class ProcrastinatorWidgetProvider : HomeWidgetProvider() { // Renamed for clarity
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_layout)

            // 1. Pull the headline description
            // "headline_description" must match the key used in HomeWidget.saveWidgetData in Dart
            val urgentTasks = widgetData.getString("headline_description", "No urgent tasks. Take a break.")
            views.setTextViewText(R.id.headline_description, urgentTasks)

            // 2. Setup the Deep Link for the Button
            val clickIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("procrastinator://create")
            )
            
            views.setOnClickPendingIntent(R.id.widget_button, clickIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}