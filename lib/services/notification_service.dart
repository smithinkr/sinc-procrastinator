import 'dart:math';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:procrastinator/utils/logger.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import '../models/task_model.dart';
import '../services/storage_service.dart';
import 'package:flutter/services.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  // ✅ Use your logger instead of print
  // This ensures the log only shows up where you want it
  L.d('SYSTEM: Notification action triggered in background: ${notificationResponse.payload}');
}
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  
  static const int _dailyId = 888; 
  static const String _channelIdCritical = 'critical_channel_v4'; 
  static const String _channelIdDaily = 'daily_briefing_channel_v4';

  Future<void> init() async {
    tz_data.initializeTimeZones();
    await requestPermissions();

    try {
  // 1. Ask the Android/iOS system directly for the local timezone ID
  // This bypasses the need for 'flutter_timezone' or 'timezone_provider'
  const MethodChannel channel = MethodChannel('flutter_timezone');
  final String? timeZoneName = await channel.invokeMethod<String>('getLocalTimezone');
  
  // 2. Fallback to IST if the system is being shy
  final String location = timeZoneName ?? 'Asia/Kolkata';
  
  tz.setLocalLocation(tz.getLocation(location));
  L.d("S.INC: Native Handshake successful. Location: $location");
} catch (e) {
  // 3. The "Emergency" Fallback
  tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
  L.d("S.INC: Native detect failed, using fallback. Error: $e");
}

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    await _notifications.initialize(
      const InitializationSettings(android: initializationSettingsAndroid),
      onDidReceiveNotificationResponse: (details) {
        L.d("Foreground notification clicked");
      },
      // 🛑 THIS IS THE MISSING LINK FOR RELEASE APKs
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    
    // 1. Explicitly create channels with MAX importance
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelIdDaily,
        'Daily Briefing',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelIdCritical, 
        'Critical Tasks', 
        importance: Importance.max,
        playSound: true,
      ),
    );

    // 2. S.INC PROACTIVE SCHEDULING (Updated for SharedPreferences/Future)
    // This solves the 'Default 7AM not working' bug by triggering 
    // updateNotifications immediately upon service initialization.
    try {
      // CRITICAL FIX: Since your StorageService now uses SharedPreferences,
      // we MUST 'await' these calls or the scheduler will crash.
      final int savedHour = await StorageService.getBriefHour() ?? 7;
      final int savedMinute = await StorageService.getBriefMinute() ?? 0;

      // Note: This also uses 'await' to ensure the schedule is locked into Android
      await updateNotifications(
        briefHour: savedHour, 
        briefMinute: savedMinute,
      );
      
      L.d("SYSTEM: Notification Service Auto-Initialized at $savedHour:${savedMinute.toString().padLeft(2, '0')}");
    } catch (e) {
      L.d("SYSTEM WARNING: Proactive scheduling failed during init: $e");
    }
  }

  /// REFRESH LOGIC: Loads tasks from storage if they aren't provided (for SettingsPage)
  Future<void> updateNotifications({
    List<Task>? allTasks,
    required int briefHour,
    required int briefMinute,
  }) async {
    // 1. Clear all existing to prevent duplicate "ghost" alarms
    await _notifications.cancelAll(); 

    // 2. Load latest tasks from storage if called from SettingsPage
    List<Task> tasksToSchedule = allTasks ?? await StorageService.loadTasks();

    // 3. Schedule Daily Brief
    await _scheduleDailyBriefing(tasksToSchedule, briefHour, briefMinute);

    // 4. Schedule 1-Hour warnings for deadlines
    final deadlineTasks = tasksToSchedule.where((t) => !t.isCompleted && t.exactDate != null).toList();
    for (var task in deadlineTasks) {
      await _scheduleCriticalAlert(task);
    }

    L.d("SYSTEM: Notifications Refreshed (Tasks: ${tasksToSchedule.length})");
  }
  @pragma('vm:entry-point')
  Future<void> _scheduleDailyBriefing(List<Task> allTasks, int hour, int minute) async {
    final now = tz.TZDateTime.now(tz.local);
    
    // 1. Calculate target for today
    var scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    
    // 2. CRITICAL FIX: If the time is within 60 seconds of now or passed, 
    // we MUST schedule for the next day to prevent the 'Past Alarm' ignore bug.
    if (scheduledDate.isBefore(now.add(const Duration(seconds: 5)))) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    int n = allTasks.where((t) => !t.isCompleted && t.exactDate != null).length;
    int x = allTasks.where((t) => !t.isCompleted && t.exactDate == null).length;

    // Uncomment for production if you don't want empty briefs
    // if (n == 0 && x == 0) return;

    bool isWeekend = scheduledDate.weekday >= 6;
    String message = getSassyBriefing(n, x, isWeekend);

    await _notifications.zonedSchedule(
      _dailyId,
      "Morning Reality Check", 
      message,                  
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelIdDaily, 
          'Daily Briefing',
          importance: Importance.max,
          priority: Priority.max,
          showWhen: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          styleInformation: BigTextStyleInformation(''),
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // Re-enables daily repetition
    );
    
    L.d("SYSTEM: Brief scheduled for $scheduledDate");
  }
  @pragma('vm:entry-point')
  Future<void> _scheduleCriticalAlert(Task task) async {
    final now = tz.TZDateTime.now(tz.local);
    if (task.exactDate == null) return; 

    final tzExactDate = tz.TZDateTime.from(task.exactDate!, tz.local);
    tz.TZDateTime scheduledDate;

    if (task.hasSpecificTime) {
      scheduledDate = tzExactDate.subtract(const Duration(hours: 1));
    } else {
      scheduledDate = tz.TZDateTime(tz.local, task.exactDate!.year, task.exactDate!.month, task.exactDate!.day, 8, 0);
    }

    if (scheduledDate.isAfter(now)) {
      await _notifications.zonedSchedule(
        task.id.hashCode,
        "DUE SOON: ${task.title}",
        "This has a deadline. Let's blame the app devs for missing it.",
        scheduledDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelIdCritical, 
            'Critical Tasks',
            importance: Importance.max,
            priority: Priority.high,
            fullScreenIntent: true,
            audioAttributesUsage: AudioAttributesUsage.alarm,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  String getSassyBriefing(int n, int x, bool isWeekend) {
    if (isWeekend) {
      return "It's the weekends, Just ignore the $n urgent and $x ignorable tasks. Be a pro.";
    }
    List<String> templates = [
      "You have $n deadlines today. 'Tomorrow You' is probably better equipped for this. Go back to sleep.",
      "There are $n urgent tasks. Conserve your energy. The work will still be there tomorrow.",
      "With $n deadlines, remember: Diamonds are made under pressure. Wait until the last second.",
      "You have $x tasks in the backlog. True peace comes from accepting you aren't doing them today.",
      "$n deadlines? Sounds like a 'Future You' problem."
    ];
    return templates[Random().nextInt(templates.length)];
  }

  Future<void> requestPermissions() async {
    final android = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.requestNotificationsPermission();
      await android.requestExactAlarmsPermission();
    }
  }

  Future<void> testNotificationNow() async {
    await _notifications.show(
      999,
      "🔔 Hardware Test",
      "If you see this, the notification system is working perfectly.",
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelIdDaily,
          'Daily Briefing',
          importance: Importance.max,
          priority: Priority.max,
        ),
      ),
    );
  }
}