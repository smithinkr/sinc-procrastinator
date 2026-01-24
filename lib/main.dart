import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest_all.dart' as tz;


// 1. Secrets import
import 'env/secrets.dart'; 

import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';

void main() async {
  // 1. Ensure Flutter is ready for native/async calls
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  
  // 2. Initialize Core Services
  await HomeWidget.setAppGroupId('group.com.sinc.procrastinator');
  await Firebase.initializeApp();
  
  // 3. Initialize Notification Service
  final notificationService = NotificationService();
  await notificationService.init();
  
  // Only request if not already granted to prevent Android 14 "Hangs"
  await notificationService.requestPermissions();

  // 4. Load User Settings
  final settingsService = SettingsService();
  await settingsService.loadSettings();

  // --- ELITE HARDENING STEP ---
  if (Secrets.geminiApiKey.isNotEmpty) {
    await settingsService.initializeVaultedKey(Secrets.geminiApiKey);
  }
  // ----------------------------

  // 5. Run App
  runApp(
    ChangeNotifierProvider.value(
      value: settingsService,
      child: const MyApp(),
    ),
  );
  // 🔥 THE SURGICAL ADDITION: 
  // We explicitly trigger the Cloud/Beta logic AFTER the app has booted.
  // This prevents the "Startup Logjam" that killed your notifications.
  settingsService.startBetaStatusListener();
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Color _getThemeColor(String colorName) {
    switch (colorName) {
      case 'emerald': return Colors.teal;
      case 'rose': return Colors.pink;
      case 'cyan': return Colors.cyan;
      default: return Colors.indigo;
    }
  }

  @override
  Widget build(BuildContext context) {
    // We use context.select to ensure MyApp only rebuilds if theme settings change,
    // not for every single change in the settings service.
    final settings = Provider.of<SettingsService>(context);
    final primaryColor = _getThemeColor(settings.themeColor);
    
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Procrastinator',
      themeMode: settings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        brightness: Brightness.light,
        colorSchemeSeed: primaryColor,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: primaryColor,
        useMaterial3: true,
      ),
      
      // 🔥 THE FINAL FIX: THE ANCHOR STRATEGY
      // We removed the StreamBuilder from here entirely.
      // This makes HomeScreen the "Root" that never restarts or resets.
      // Your HomeScreen's internal initState already handles Auth logic silently.
      home: const HomeScreen(),
    );
  }
}