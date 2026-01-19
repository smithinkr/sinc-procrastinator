import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:provider/provider.dart';

// 1. Remove flutter_dotenv and import your generated Env class
import 'env/secrets.dart'; 

import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';


void main() async {
  // 1. Ensure Flutter is ready for native/async calls
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. Initialize Core Services
  await HomeWidget.setAppGroupId('group.com.sinc.procrastinator');
  await Firebase.initializeApp();
  
  // 3. Initialize Notification Service
  final notificationService = NotificationService();
  await notificationService.init();
  await notificationService.requestPermissions();

  // 4. Load User Settings
  final settingsService = SettingsService();
  await settingsService.loadSettings();
  // 2. The "Secure Tag": Initialize the S.Inc encryption vault


  // --- ELITE HARDENING STEP ---
  // We no longer load a .env file from assets. 
  // Instead, we pull the scrambled key from the compiled Env class 
  // and move it into the Hardware Vault immediately.
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
      home: const HomeScreen(),
    );
  }
}