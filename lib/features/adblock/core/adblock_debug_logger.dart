import 'package:flutter/foundation.dart';

class AdblockDebugLogger {
  AdblockDebugLogger({
    required bool enabled,
    this.maxLogs = 1200,
  }) : _enabled = enabled;

  final int maxLogs;
  bool _enabled;
  int _logCount = 0;

  bool get enabled => _enabled;

  void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  void log(String message) {
    if (!_enabled || !kDebugMode || _logCount >= maxLogs) {
      return;
    }
    _logCount += 1;
    debugPrint('[GO_PLAY-Adblock] $message');
  }

  void reset() {
    _logCount = 0;
  }
}
