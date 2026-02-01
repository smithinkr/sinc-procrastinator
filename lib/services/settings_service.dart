import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:procrastinator/utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'storage_service.dart';
import 'notification_service.dart';
// import 'security_service.dart'; // 🧊 FROZEN: Re-enable for local key vaulting

class SettingsService with ChangeNotifier {
  String _themeColor = 'emerald';
  bool _isDarkMode = false;
  double _aiCreativity = 0.7; 
  bool _isAiEnabled = false; 
  int _briefHour = 7; 
  int _briefMinute = 0;
  bool _isHudEnabled = true;
  bool _isBetaApproved = false;

  SettingsService();

  StreamSubscription<DocumentSnapshot>? _betaListener;

  // --- GETTERS ---
  String get themeColor => _themeColor;
  bool get isDarkMode => _isDarkMode;
  double get aiCreativity => _aiCreativity;
  bool get isAiEnabled => _isAiEnabled;
  int get briefHour => _briefHour;
  int get briefMinute => _briefMinute;
  bool get isHudEnabled => _isHudEnabled;
  bool get isBetaApproved => _isBetaApproved;

  // --- ⚡ BETA STATUS LISTENER ---
  void startBetaStatusListener() {
    stopBetaListener(); 

    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        L.d("👤 IDENTITY: Syncing Beta Status for ${user.uid}...");
        
        _betaListener = FirebaseFirestore.instance 
            .collection('users')
            .doc(user.uid)
            .snapshots()
            .listen((snapshot) async {
              if (snapshot.exists && snapshot.data() != null) {
                final data = snapshot.data() as Map<String, dynamic>;
                _isBetaApproved = data['isBetaApproved'] ?? false;
                
                if (_isBetaApproved && !_isAiEnabled) {
                  _isAiEnabled = true;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('isAiEnabled', true);
                  L.d("🔓 S.INC: AI Features auto-unlocked for approved beta user.");
                }

                if (_isBetaApproved) {
                  L.d("✅ S.INC: User is officially approved.");
                }

                notifyListeners();
                L.d("📡 S.INC CLOUD: Beta Status -> $_isBetaApproved");
              }
            });
      } else {
        L.d("👤 IDENTITY: No user session found.");
        stopBetaListener();
      }
    });
  }

  void stopBetaListener() {
    _betaListener?.cancel();
    _betaListener = null;
    _isBetaApproved = false;
    notifyListeners();
  }

  /* 🧊 LEGACY REVERSION POINT: Local Key Access
  Future<String> getSecureApiKey() async {
    try {
      return await SecurityService.getSecret('gemini_api_key') ?? '';
    } catch (e) {
      L.d("⚠️ Memory-Safe Vault Access Error: $e");
      return '';
    }
  }
  */

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    _themeColor = prefs.getString('themeColor') ?? 'emerald';
    _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    _aiCreativity = prefs.getDouble('aiCreativity') ?? 0.7;
    _isAiEnabled = prefs.getBool('isAiEnabled') ?? false;
    _briefHour = prefs.getInt('briefHour') ?? 7;
    _briefMinute = prefs.getInt('briefMinute') ?? 0;
    _isHudEnabled = prefs.getBool('isHudEnabled') ?? true;

    /* 🧊 LEGACY REVERSION POINT: Local Key Check
    final hasKey = (await SecurityService.getSecret('gemini_api_key'))?.isNotEmpty ?? false;
    if (hasKey) {
      _isAiEnabled = true;
    }
    */
    notifyListeners();
  }

  /* 🧊 LEGACY REVERSION POINT: Key Vaulting Logic
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
  */

  // --- UPDATERS ---
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

    try {
      final String? currentUid = FirebaseAuth.instance.currentUser?.uid;
      final tasks = await StorageService.loadTasks(currentUid);
      
      await NotificationService().updateNotifications(
        allTasks: tasks,
        briefHour: hour,
        briefMinute: minute,
        uid: currentUid,
      );
      L.d("🔔 S.INC: Morning Brief rescheduled.");
    } catch (e) {
      L.d("🚨 S.INC: Failed to hot-swap notification schedule: $e");
    }
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

  @override
  void dispose() {
    _betaListener?.cancel();
    super.dispose();
  }
}