import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import '../services/storage_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

// 1. Secrets import
import 'env/secrets.dart'; 

import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  
  await HomeWidget.setAppGroupId('group.com.sinc.procrastinator');
  await Firebase.initializeApp();
  
  final notificationService = NotificationService();
  await notificationService.init();
  await notificationService.requestPermissions();

  final settingsService = SettingsService();
  await settingsService.loadSettings();

  if (Secrets.geminiApiKey.isNotEmpty) {
    await settingsService.initializeVaultedKey(Secrets.geminiApiKey);
  }

  // Visual Hint for the initial (fast storage)
  final authHint = await StorageService.getAuthHint();
  final String userInitial = authHint?['initial'] ?? "";

  runApp(
    ChangeNotifierProvider.value(
      value: settingsService,
      child: MyApp(initial: userInitial),
    ),
  );

  settingsService.startBetaStatusListener();
}

class MyApp extends StatelessWidget {
  final String initial;
  const MyApp({super.key, required this.initial});

  @override
  Widget build(BuildContext context) {
    // 🛡️ S.INC SHIELD: The Selector stops the "Blink"
    // It filters out Task saves and only watches for Theme/Dark Mode.
    return Selector<SettingsService, (bool, String)>(
      selector: (_, settings) => (settings.isDarkMode, settings.themeColor),
      builder: (context, data, child) {
        final isDarkMode = data.$1;
        final themeColorName = data.$2;
        final primaryColor = _getThemeColor(themeColorName);

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Procrastinator',
          themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
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
          // home stays anchored here, but won't rebuild on task saves
          home: AuthGate(userInitial: initial),
        );
      },
    );
  }

  Color _getThemeColor(String colorName) {
    switch (colorName) {
      case 'emerald': return Colors.teal;
      case 'rose': return Colors.pink;
      case 'cyan': return Colors.cyan;
      default: return Colors.indigo;
    }
  }
}

// 🚪 THE AUTH GATE: Separate class to prevent UI reboots during data saves
class AuthGate extends StatelessWidget {
  final String userInitial;
  const AuthGate({super.key, required this.userInitial});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        
        // 1. THE BUFFER (Only shows on actual boot/logout)
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: Text(
                "Let's procrastinate in style", 
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          );
        }

        // 2. THE TRUTH: Session is active
        if (snapshot.hasData && snapshot.data != null) {
          return HomeScreen(
            startLoggedIn: true, 
            userInitial: userInitial.isNotEmpty ? userInitial : (snapshot.data!.displayName?[0] ?? "S"),
          );
        }

        // 3. FALLBACK: User is logged out
        return const HomeScreen(
          startLoggedIn: false, 
          userInitial: "",
        );
      },
    );
  }
}