import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class GatekeeperService {
  static const _storage = FlutterSecureStorage();
  static const _keyName = "beta_unlocked_status";

  // This checks if the app is already unlocked
  static Future<bool> isAiUnlocked() async {
    String? status = await _storage.read(key: _keyName);
    return status == "true";
  }

  // This checks if the key entered is correct
  static Future<bool> verifyAndUnlock(String inputKey) async {
    // You can change this 'SECRET123' to whatever key you want
    if (inputKey == "SINC-BETA-2026") {
      await _storage.write(key: _keyName, value: "true");
      return true;
    }
    return false;
  }
}