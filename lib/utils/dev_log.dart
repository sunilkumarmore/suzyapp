import 'package:flutter/foundation.dart';

class DevLog {
  // Enable with:
  // flutter run --dart-define=SUZY_LOG_NARRATION=true
  // flutter run --dart-define=SUZY_LOG_COLORING=true
  static const bool _all = bool.fromEnvironment('SUZY_LOG_ALL', defaultValue: false);
  static const bool _narration = bool.fromEnvironment('SUZY_LOG_NARRATION', defaultValue: false);
  static const bool _coloring = bool.fromEnvironment('SUZY_LOG_COLORING', defaultValue: false);

  static bool get narrationEnabled => kDebugMode && (_all || _narration);
  static bool get coloringEnabled => kDebugMode && (_all || _coloring);

  static void narration(String message) {
    if (!narrationEnabled) return;
    debugPrint('[Narration] $message');
  }

  static void coloring(String message) {
    if (!coloringEnabled) return;
    debugPrint('[Coloring] $message');
  }
}
