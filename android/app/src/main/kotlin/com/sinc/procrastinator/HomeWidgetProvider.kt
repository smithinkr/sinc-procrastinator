package com.sinc.procrastinator

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import android.net.Uri
import es.antonborri.home_widget.HomeWidgetProvider
import es.antonborri.home_widget.HomeWidgetLaunchIntent

class ProcrastinatorWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            // Update this to match your new filename: widget_layout
            val views = RemoteViews(context.packageName, R.layout.widget_layout)

            // 1. Pull the headline description
            val urgentTasks = widgetData.getString("headline_description", "No urgent tasks. Take a break.")
            views.setTextViewText(R.id.headline_description, urgentTasks)

            // 2. Setup the "Open App" Intent for the Body (Widget Container)
            // We use a simple URI here so it just opens the main app
            val bodyIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java
            )
            // "widget_container" must match the android:id you gave to the RelativeLayout
            views.setOnClickPendingIntent(R.id.widget_container, bodyIntent)

            // 3. Setup the Deep Link for the Button (The Plus Icon)
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