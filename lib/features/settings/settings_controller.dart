import 'package:flutter/foundation.dart';

class SettingsController extends ChangeNotifier {
  SettingsController({
    bool adblockEnabled = true,
    bool pipEnabled = true,
    bool backgroundPlaybackEnabled = true,
  }) : _adblockEnabled = adblockEnabled,
       _pipEnabled = pipEnabled,
       _backgroundPlaybackEnabled = backgroundPlaybackEnabled;

  bool _adblockEnabled;
  bool _pipEnabled;
  bool _backgroundPlaybackEnabled;

  bool get adblockEnabled => _adblockEnabled;
  bool get pipEnabled => _pipEnabled;
  bool get backgroundPlaybackEnabled => _backgroundPlaybackEnabled;

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

  void setBackgroundPlaybackEnabled(bool enabled) {
    if (_backgroundPlaybackEnabled == enabled) {
      return;
    }
    _backgroundPlaybackEnabled = enabled;
    notifyListeners();
  }
}
