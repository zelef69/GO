import 'package:flutter/foundation.dart';

class SettingsController extends ChangeNotifier {
  SettingsController({
    bool adblockEnabled = true,
    bool pipEnabled = true,
  })  : _adblockEnabled = adblockEnabled,
        _pipEnabled = pipEnabled;

  bool _adblockEnabled;
  bool _pipEnabled;

  bool get adblockEnabled => _adblockEnabled;
  bool get pipEnabled => _pipEnabled;

  void setAdblockEnabled(bool enabled) {
    if (_adblockEnabled == enabled) {
      return;
    }
    _adblockEnabled = enabled;
    notifyListeners();
  }

  void setPiPEnabled(bool enabled) {
    if (_pipEnabled == enabled) {
      return;
    }
    _pipEnabled = enabled;
    notifyListeners();
  }
}
