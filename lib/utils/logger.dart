import 'package:flutter/foundation.dart';

class L {
  /// Standard Debug Log - Only visible in your VS Code console
  static void d(String message) {
    if (kDebugMode) {
      print("🛠️ [DEBUG]: $message"); 
    }
  }

  /// Error Log - Use for catching exceptions
  static void e(String message, [dynamic error]) {
    if (kDebugMode) {
      // We use debugPrint here because it handles long error messages better
      debugPrint("🚨 [ERROR]: $message ${error ?? ''}");
    }
  }
}