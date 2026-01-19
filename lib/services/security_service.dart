import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:procrastinator/utils/logger.dart';

class SecurityService {
  static const _storage = FlutterSecureStorage(
    // EncryptedSharedPreferences uses the Android Keystore (Hardware Security)
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true, // Crucial: Prevents crashes if the Keystore is corrupted
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  /// Saves a secret only if it doesn't already exist, unless [overwrite] is true.
  static Future<void> saveSecret(String key, String value, {bool overwrite = false}) async {
    try {
      if (!overwrite) {
        final existing = await _storage.read(key: key);
        if (existing != null) {
          L.d("⚠️ SECURITY_SERVICE: Attempted to overwrite existing key: $key. Aborting.");
          return;
        }
      }
      await _storage.write(key: key, value: value);
    } catch (e) {
      L.d("🚨 SECURITY_SERVICE WRITE ERROR: $e");
      rethrow; // We want the app to know if hardware storage failed
    }
  }

  static Future<String?> getSecret(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      L.d("🚨 SECURITY_SERVICE READ ERROR: $e");
      return null;
    }
  }

  static Future<void> deleteSecret(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      L.d("🚨 SECURITY_SERVICE DELETE ERROR: $e");
    }
  }
}