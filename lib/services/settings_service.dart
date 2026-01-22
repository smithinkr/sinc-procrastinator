import 'dart:async'; // MANDATORY: For Beta Listener
import 'package:flutter/foundation.dart';
import 'package:procrastinator/utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // MANDATORY: For Beta Check

import 'security_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
 // Ensure this is there too

class SettingsService with ChangeNotifier {
  String _themeColor = 'indigo';
  bool _isDarkMode = false;
  double _aiCreativity = 0.7; 
  bool _isAiEnabled = false; 
  int _briefHour = 7; 
  int _briefMinute = 0;
  bool _isHudEnabled = true;
  bool _isBetaApproved = false;
  
  
  // ADD THIS CONSTRUCTOR:
SettingsService() {
  loadSettings();

  // THE REACTIVE FIX: Wait for the Auth state to be "Solid"
  FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user != null) {
      L.d("👤 IDENTITY: User confirmed (${user.uid}). Syncing Beta Status...");
      startBetaStatusListener(); // This flips your UI to 'Verified' instantly
    } else {
      L.d("👤 IDENTITY: No user found. Features locked.");
      stopBetaListener();
    }
  });
}

  // --- NEW BETA STATE (MANDATORY) ---
  
 
  StreamSubscription<DocumentSnapshot>? _betaListener;

  // --- GETTERS ---
  String get themeColor => _themeColor;
  bool get isDarkMode => _isDarkMode;
  double get aiCreativity => _aiCreativity;
  bool get isAiEnabled => _isAiEnabled;
  int get briefHour => _briefHour;
  int get briefMinute => _briefMinute;
  bool get isHudEnabled => _isHudEnabled;
  bool get isBetaApproved => _isBetaApproved; // FIXES HOMESCREEN ERROR

  // --- NEW BETA LISTENER (MANDATORY) ---

  void startBetaStatusListener() {
  stopBetaListener(); // Clean up any old ones first

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  // Catch the stream here!
  _betaListener = FirebaseFirestore.instance 
      .collection('users')
      .doc(user.uid)
      .snapshots()
      .listen((snapshot) async {
        if (snapshot.exists && snapshot.data() != null) {
          final data = snapshot.data() as Map<String, dynamic>;
          _isBetaApproved = data['isBetaApproved'] ?? false;
          // LOGIC: If they are approved, we don't care about the pending list anymore!
    if (_isBetaApproved && !_isAiEnabled) {
              _isAiEnabled = true;
              
              // Save to permanent storage so it stays ON after restart
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('isAiEnabled', true);
              
              L.d("🔓 S.INC: AI Features auto-unlocked for approved beta user.");
            }

    if (_isBetaApproved) {
      L.d("✅ S.INC: User is officially approved. Clearing UI noise.");
    }
          notifyListeners();
          
          // Use your custom logger 'L' instead of print
          L.d("📡 S.INC CLOUD: Beta Status -> $_isBetaApproved");
        }
      });
}

  void stopBetaListener() {
    _betaListener?.cancel();
    _betaListener = null;
    _isBetaApproved = false;
    notifyListeners();
  }

  /// CRITICAL CHANGE: We no longer store the API key in a String variable.
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
    _isHudEnabled = prefs.getBool('isHudEnabled') ?? true;

    final hasKey = (await SecurityService.getSecret('gemini_api_key'))?.isNotEmpty ?? false;
    if (hasKey) {
      _isAiEnabled = true;
    }
    notifyListeners();
  }
  

  Future<void> initializeVaultedKey(String keyFromConfig) async {
    if (keyFromConfig.isEmpty) return;
    try {
      await SecurityService.saveSecret('gemini_api_key', keyFromConfig);
      _isAiEnabled = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('gemini_api_key'); 
      notifyListeners();
      L.d("✅ API Key successfully vaulted and removed from RAM path.");
    } catch (e) {
      L.d("⚠️ Vault Initialization Error: $e");
    }
  }

  // --- STANDARD UPDATERS (KEEPING YOUR LOGS INTACT) ---
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

  // CLEANUP
  @override
  void dispose() {
    _betaListener?.cancel();
    super.dispose();
  }
}