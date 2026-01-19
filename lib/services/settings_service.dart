import 'package:flutter/foundation.dart';
import 'package:procrastinator/utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'security_service.dart';

class SettingsService with ChangeNotifier {
  String _themeColor = 'indigo';
  bool _isDarkMode = false;
  double _aiCreativity = 0.7; 
  bool _isAiEnabled = false; 
  int _briefHour = 7; 
  int _briefMinute = 0;
  bool _isHudEnabled = true; // Default to visible

  // --- GETTERS ---
  String get themeColor => _themeColor;
  bool get isDarkMode => _isDarkMode;
  double get aiCreativity => _aiCreativity;
  bool get isAiEnabled => _isAiEnabled;
  int get briefHour => _briefHour;
  int get briefMinute => _briefMinute;
  bool get isHudEnabled => _isHudEnabled;

  /// CRITICAL CHANGE: We no longer store the API key in a String variable.
  /// This prevents the key from being captured in a memory dump.
  Future<String> getSecureApiKey() async {
    try {
      return await SecurityService.getSecret('gemini_api_key') ?? '';
    } catch (e) {
      L.d("⚠️ Memory-Safe Vault Access Error: $e");
      return '';
    }
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    _themeColor = prefs.getString('themeColor') ?? 'indigo';
    _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    _aiCreativity = prefs.getDouble('aiCreativity') ?? 0.7;
    _isAiEnabled = prefs.getBool('isAiEnabled') ?? false;
    _briefHour = prefs.getInt('briefHour') ?? 7;
    _briefMinute = prefs.getInt('briefMinute') ?? 0;
    _isHudEnabled = prefs.getBool('isHudEnabled') ?? true; // Load HUD preference

    // Check if a key exists to determine if AI features should be visible,
    // but DO NOT store the key itself in this class.
    final hasKey = (await SecurityService.getSecret('gemini_api_key'))?.isNotEmpty ?? false;
    
    if (hasKey) {
      _isAiEnabled = true;
    }
    
    notifyListeners();
  }

  /// Use this to initialize the app with the key from your .env or ENVied class
  Future<void> initializeVaultedKey(String keyFromConfig) async {
    if (keyFromConfig.isEmpty) return;

    try {
      // Save to hardware-backed storage
      await SecurityService.saveSecret('gemini_api_key', keyFromConfig);
      _isAiEnabled = true;
      
      // Cleanup: Ensure the key isn't sitting in insecure prefs from old versions
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('gemini_api_key'); 
      
      notifyListeners();
      L.d("✅ API Key successfully vaulted and removed from RAM path.");
    } catch (e) {
      L.d("⚠️ Vault Initialization Error: $e");
    }
  }

  // --- STANDARD UPDATERS ---
  Future<void> toggleHud(bool isEnabled) async {
    _isHudEnabled = isEnabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isHudEnabled', isEnabled);
    L.d("SYSTEM: HUD Visibility toggled to $isEnabled");
  }

  Future<void> toggleAiFeatures(bool isEnabled) async {
    _isAiEnabled = isEnabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isAiEnabled', isEnabled);
  }

  Future<void> updateBriefTime(int hour, int minute) async {
    _briefHour = hour;
    _briefMinute = minute;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('briefHour', hour);
    await prefs.setInt('briefMinute', minute);
  }

  Future<void> updateAiCreativity(double value) async {
    _aiCreativity = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('aiCreativity', value);
  }

  Future<void> updateTheme(String color, bool isDark) async {
    _themeColor = color;
    _isDarkMode = isDark;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeColor', color);
    await prefs.setBool('isDarkMode', isDark);
  }
}