import 'dart:convert';
import 'package:flutter/foundation.dart'; 
import 'package:procrastinator/utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import '../models/task_model.dart';
import 'security_service.dart';

class StorageService {
  // Using a new key for V2 to avoid format conflicts with old CBC data
  static const String _tasksKey = 'procrastinator_tasks_secure_v2';
  static const String _masterKeyName = 'task_encryption_master_key_v2';   

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

  static Future<void> saveTasks(List<Task> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _getEncryptionKey();

    // Map tasks to JSON first to simplify data transfer to the isolate
    final List<Map<String, dynamic>> taskMap = tasks.map((t) => t.toJson()).toList();

    // Move encryption to a background thread to prevent UI freeze
    final String secureData = await compute(_encryptWorker, {
      'tasksJson': jsonEncode(taskMap),
      'key': key,
    });

    await prefs.setString(_tasksKey, secureData);
  }

  static Future<List<Task>> loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final String? rawData = prefs.getString(_tasksKey);

    if (rawData == null || !rawData.contains(':')) return [];

    try {
      final key = await _getEncryptionKey();

      // Move decryption to a background thread to prevent UI freeze
      final String decryptedJson = await compute(_decryptWorker, {
        'rawData': rawData,
        'key': key,
      });

      final List<dynamic> decoded = jsonDecode(decryptedJson);
      return decoded.map((item) => Task.fromJson(item)).toList();
    } catch (e) {
      L.d("🚨 STORAGE_SERVICE ERROR: Tampering or corruption detected. $e");
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
}