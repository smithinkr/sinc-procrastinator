import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import '../services/storage_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'; // Required for kDebugMode
import 'package:firebase_app_check/firebase_app_check.dart'; // The security library

// 1. Secrets import
import 'env/secrets.dart'; 

import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Handles the "Fresh Install" check
import 'onboarding_screen.dart'; // Imports your new hint slides

final GlobalKey<NavigatorState> sIncNavigatorKey = GlobalKey<NavigatorState>();
  void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  
  await HomeWidget.setAppGroupId('group.com.sinc.procrastinator');
  await Firebase.initializeApp();
  // main.dart
// 🛡️ S.INC SHIELD: The official 2026 standard for App Check
// 🛡️ S.INC SHIELD: Modern 2026 App Check Initialization
await FirebaseAppCheck.instance.activate(
  // 1. Android: Use 'providerAndroid' and the new Provider classes
  providerAndroid: kDebugMode 
      ? const AndroidDebugProvider() 
      : const AndroidPlayIntegrityProvider(),
  
  // 2. Apple: Use 'providerApple' and the new Provider classes
  providerApple: kDebugMode 
      ? const AppleDebugProvider() 
      : const AppleAppAttestWithDeviceCheckFallbackProvider(),
);
 
  
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
  final prefs = await SharedPreferences.getInstance();
  final bool isReturning = prefs.getBool('onboarding_done') ?? false;

  runApp(
    ChangeNotifierProvider.value(
      value: settingsService,
      child: MyApp(initial: userInitial, isReturning: isReturning),
    ),
  );

  settingsService.startBetaStatusListener();
}

class MyApp extends StatefulWidget {
  final String initial;
  final bool isReturning;
  const MyApp({super.key, required this.initial, required this.isReturning});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // 🛡️ S.INC SHIELD: Static caching is the "Nuclear Option."
  // By making it static, the instance is held at the Class level, 
  // making it physically impossible for the Navigator to "re-init" it on Pop.
  static Widget? _cachedRoot;

  @override
  void initState() {
    super.initState();
    // 🛡️ S.INC SHIELD: Only initialize if it doesn't exist.
    // This keeps the AppStartSwitcher "Hot" in memory forever.
    _cachedRoot ??= AppStartSwitcher(
      key: const ValueKey('SINC_IMMUTABLE_ROOT'), 
      userInitial: widget.initial,
      isReturning: widget.isReturning,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: sIncNavigatorKey, // ⚓ LOCK THE STACK
  home: _cachedRoot, // Points to your static root
      debugShowCheckedModeBanner: false,
      title: 'Procrastinator',
      // 🎯 We point to the static cache.
      builder: (context, child) {
        return Selector<SettingsService, (bool, String)>(
          selector: (_, settings) => (settings.isDarkMode, settings.themeColor),
          builder: (context, data, _) {
            final isDarkMode = data.$1;
            final themeColorName = data.$2;

            return Theme(
              data: ThemeData(
                brightness: isDarkMode ? Brightness.dark : Brightness.light,
                colorSchemeSeed: _getThemeColor(themeColorName),
                useMaterial3: true,
              ),
              // 🛡️ S.INC SHIELD: 'child' is our _cachedRoot.
              // We use child! here to ensure the internal Navigator 
              // treats it as a persistent singleton.
              child: child!, 
            );
          },
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

// 🚪 THE AUTH GATE: Separate class to prxevent UI reboots during data saves
class AuthGate extends StatelessWidget {
  final String userInitial;
  const AuthGate({super.key, required this.userInitial});

  @override
Widget build(BuildContext context) {
  return StreamBuilder<User?>(
    stream: FirebaseAuth.instance.authStateChanges(),
    builder: (context, snapshot) {
      // 🛡️ S.INC SHIELD: THE PERSISTENCE GUARD
      // In Release mode, returning from Settings triggers a 'waiting' state.
      // We check if we ALREADY HAVE data. If we do, we skip the splash screen.
      if (snapshot.hasData && snapshot.data != null) {
        return HomeScreen(
          startLoggedIn: true,
          userInitial: userInitial.isNotEmpty 
              ? userInitial 
              : (snapshot.data!.displayName?[0] ?? "S"),
        );
      }

      // 1. THE BUFFER (Only shows on absolute COLD BOOT or LOGOUT)
      // We only enter here if there is NO data and we are still waiting.
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

      // 3. FALLBACK: User is confirmed logged out
      return const HomeScreen(
        startLoggedIn: false,
        userInitial: "",
      );
    },
  );
}
  
}
// 🧭 THE TRAFFIC CONTROLLER: Decides between Hints and Auth
class AppStartSwitcher extends StatelessWidget { // 👈 Change to StatelessWidget
  final String userInitial;
  final bool isReturning;
  const AppStartSwitcher({super.key, required this.userInitial, required this.isReturning});

  @override
  Widget build(BuildContext context) {
    // 🛡️ S.INC SHIELD: No more waiting state. Decision is instant.
    if (isReturning) {
      return AuthGate(userInitial: userInitial);
    } else {
      return const OnboardingScreen();
    }
  }
}

