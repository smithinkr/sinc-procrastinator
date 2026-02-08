import 'dart:convert';
import 'package:flutter/foundation.dart'; 
import 'package:procrastinator/utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import '../models/task_model.dart';
import 'security_service.dart';


class StorageService {
  // Using a new key for V2 to avoid format conflicts with old CBC data
  static const String _masterKeyName = 'task_encryption_master_key_v2'; 
  static const String _authKey = 'procrastinator_auth_hint_v2';  
  static const String _baseTaskKey = 'procrastinator_tasks_';
  
  /// --- INTERNAL HELPERS ---
  static Future<int?> getBriefHour() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('brief_hour'); // Returns null if never set
  }

  static Future<int?> getBriefMinute() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('brief_minute'); // Returns null if never set
  }

  static Future<void> saveBriefTime(int hour, int minute) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('brief_hour', hour);
    await prefs.setInt('brief_minute', minute);
  }
  static Future<bool> isHudEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    // Default to true so new users see the HUD immediately
    return prefs.getBool('show_hud') ?? true; 
  }
  static Future<void> saveBool(String key, bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(key, value);
}

static Future<bool?> getBool(String key) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(key);
}

  static Future<void> setHudEnabled(bool visible) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_hud', visible);
  }

  static Future<encrypt.Key> _getEncryptionKey() async {
    String? existingKey = await SecurityService.getSecret(_masterKeyName);
    if (existingKey == null) {
      // 32 bytes for a 256-bit AES key
      final newKey = encrypt.Key.fromSecureRandom(32).base64;
      await SecurityService.saveSecret(_masterKeyName, newKey);
      existingKey = newKey;
    }
    return encrypt.Key.fromBase64(existingKey);
  }

  /// --- PUBLIC API ---

  static Future<void> saveTasks(List<Task> tasks, String? uid) async {
  final prefs = await SharedPreferences.getInstance();
  final key = await _getEncryptionKey();

  // 🔥 THE WALL: Determine which specific vault to open
  final String storageKey = "$_baseTaskKey${uid ?? 'guest'}";

  // Map tasks to JSON
  final List<Map<String, dynamic>> taskMap = tasks.map((t) => t.toJson()).toList();

  // MOVE TO ISOLATE: Encrypt in the background to prevent UI stutter
  final String secureData = await compute(_encryptWorker, {
    'tasksJson': jsonEncode(taskMap),
    'key': key,
  });

  await prefs.setString(storageKey, secureData);
  L.d("🔒 S.INC: Data secured in vault: $storageKey");
}

  static Future<void> clearAll() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('tasks'); // The key where we store your task list
    L.d("💾 S.INC: Local Hardware Vault wiped successfully.");
  } catch (e) {
    L.d("🚨 S.INC: Local Wipe Error: $e");
  }
}

 static Future<List<Task>> loadTasks(String? uid) async {
  final prefs = await SharedPreferences.getInstance();
  
  // 🔥 THE WALL: Look for the specific passport-matched file
  final String storageKey = "$_baseTaskKey${uid ?? 'guest'}";
  final String? rawData = prefs.getString(storageKey);

  if (rawData == null || !rawData.contains(':')) {
    L.d("📂 S.INC: No existing vault found for $storageKey. Starting fresh.");
    return [];
  }

  try {
    final key = await _getEncryptionKey();

    // MOVE TO ISOLATE: Decrypt in the background
    final String decryptedJson = await compute(_decryptWorker, {
      'rawData': rawData,
      'key': key,
    });

    final List<dynamic> decoded = jsonDecode(decryptedJson);
    return decoded.map((item) => Task.fromJson(item)).toList();
  } catch (e) {
    L.d("🚨 S.INC STORAGE ERROR: Tampering or corruption detected in $storageKey. $e");
    return [];
  }
}

  /// --- BACKGROUND WORKERS (ISOLATES) ---

  static String _encryptWorker(Map<String, dynamic> data) {
    final String tasksJson = data['tasksJson'];
    final encrypt.Key key = data['key'];

    // AES-GCM standard recommends a 12-byte (96-bit) IV/nonce
    final iv = encrypt.IV.fromSecureRandom(12);
    
    // Explicitly set AESMode.gcm
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));

    final encrypted = encrypter.encrypt(tasksJson, iv: iv);

    // In the 'encrypt' package, the GCM auth tag is automatically appended 
    // to the encrypted bytes when using AESMode.gcm.
    return "${iv.base64}:${encrypted.base64}";
  }

  static String _decryptWorker(Map<String, dynamic> data) {
    final String rawData = data['rawData'];
    final encrypt.Key key = data['key'];

    final parts = rawData.split(':');
    final iv = encrypt.IV.fromBase64(parts[0]);
    final encryptedContent = encrypt.Encrypted.fromBase64(parts[1]);

    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));
    
    // If the data was tampered with (even by one bit), GCM's authentication 
    // tag check will fail here and throw an exception.
    return encrypter.decrypt(encryptedContent, iv: iv);
  }
  static Future<void> saveAuthHint({
  required String initial, 
  required bool isActive, 
  String? photoUrl, // Nullable, because a user might not have a photo
}) async {
  final prefs = await SharedPreferences.getInstance();
  final key = await _getEncryptionKey();

  final Map<String, dynamic> authData = {
    'initial': initial,
    'isActive': isActive,
    'photoUrl': photoUrl,
    'lastCheck': DateTime.now().toIso8601String(),
  };

  final String secureData = await compute(_encryptWorker, {
    'tasksJson': jsonEncode(authData), // We reuse the worker logic
    'key': key,
  });

  await prefs.setString(_authKey, secureData);
}

static Future<Map<String, dynamic>?> getAuthHint() async {
  final prefs = await SharedPreferences.getInstance();
  final String? rawData = prefs.getString(_authKey);

  if (rawData == null || !rawData.contains(':')) return null;

  try {
    final key = await _getEncryptionKey();
    final String decryptedJson = await compute(_decryptWorker, {
      'rawData': rawData,
      'key': key,
    });

    return jsonDecode(decryptedJson);
  } catch (e) {
    return null;
  }
}

static Future<void> clearAuthHint() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_authKey);
}
}