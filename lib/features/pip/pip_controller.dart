import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'pip_channel.dart';
import 'pip_video_state.dart';

class PiPController {
  PiPController({required PiPChannel channel}) : _channel = channel;

  final PiPChannel _channel;

  PiPVideoState _state = PiPVideoState.empty();
  bool _pipEnabled = true;
  bool _isInPiPMode = false;
  bool _nativeAvailable = true;

  PiPVideoState get state => _state;
  bool get isInPiPMode => _isInPiPMode;

  Future<void> initialize({
    required bool pipEnabled,
    required bool backgroundPlaybackEnabled,
  }) async {
    _pipEnabled = pipEnabled;
    await _guardVoid(
      operation: 'setPiPEnabled',
      action: () => _channel.setPiPEnabled(pipEnabled),
    );
    await _guardVoid(
      operation: 'setBackgroundPlaybackEnabled',
      action: () =>
          _channel.setBackgroundPlaybackEnabled(backgroundPlaybackEnabled),
    );
    await _guardVoid(
      operation: 'setAppInForeground',
      action: () => _channel.setAppInForeground(true),
    );
    await _sendStateToNative();
  }

  Future<void> setPiPEnabled(bool enabled) async {
    _pipEnabled = enabled;
    await _guardVoid(
      operation: 'setPiPEnabled',
      action: () => _channel.setPiPEnabled(enabled),
    );
  }

  Future<void> setBackgroundPlaybackEnabled(bool enabled) async {
    await _guardVoid(
      operation: 'setBackgroundPlaybackEnabled',
      action: () => _channel.setBackgroundPlaybackEnabled(enabled),
    );
  }

  Future<void> setAppInForeground(bool inForeground) async {
    await _guardVoid(
      operation: 'setAppInForeground',
      action: () => _channel.setAppInForeground(inForeground),
    );
  }

  void setMethodCallHandler(
    Future<dynamic> Function(MethodCall call)? handler,
  ) {
    _channel.setMethodCallHandler(handler);
  }

  void setPiPMode(bool isInPiPMode) {
    _isInPiPMode = isInPiPMode;
  }

  Future<void> updateState(PiPVideoState nextState) async {
    _state = nextState;
    await _sendStateToNative();
  }

  Future<bool> enterPiPWithState(PiPVideoState nextState) async {
    _state = nextState;
    await _sendStateToNative();
    if (!_pipEnabled || !_state.isPlaying) {
      return false;
    }
    return _guardBool(
      operation: 'enterPiPIfEligible',
      fallback: false,
      action: () => _channel.enterPiPIfEligible(),
    );
  }

  Future<bool> refreshPiPModeFromNative() async {
    final nativeInPiP = await _guardBool(
      operation: 'isInPiPMode',
      fallback: false,
      action: () => _channel.isInPiPMode(),
    );
    _isInPiPMode = nativeInPiP;
    return nativeInPiP;
  }

  Future<void> _sendStateToNative() async {
    await _guardVoid(
      operation: 'setVideoState',
      action: () => _channel.setVideoState(
        isPlaying: _state.isPlaying,
        isFullscreen: _state.isFullscreen,
        videoWidth: _state.videoWidth,
        videoHeight: _state.videoHeight,
        videoRectLeft: _state.videoRectLeft,
        videoRectTop: _state.videoRectTop,
        videoRectRight: _state.videoRectRight,
        videoRectBottom: _state.videoRectBottom,
        title: _state.title,
        author: _state.author,
        durationMs: _state.durationMs,
        positionMs: _state.positionMs,
        hasNext: _state.hasNext,
      ),
    );
  }

  Future<void> _guardVoid({
    required String operation,
    required Future<void> Function() action,
  }) async {
    if (!_nativeAvailable) {
      return;
    }
    try {
      await action();
    } on MissingPluginException catch (error) {
      _nativeAvailable = false;
      _logNativeUnavailable(operation, error);
    } on PlatformException catch (error) {
      _nativeAvailable = false;
      _logNativeUnavailable(
        operation,
        '${error.code}${error.message == null ? '' : ': ${error.message}'}',
      );
    }
  }

  Future<bool> _guardBool({
    required String operation,
    required bool fallback,
    required Future<bool> Function() action,
  }) async {
    if (!_nativeAvailable) {
      return fallback;
    }
    try {
      return await action();
    } on MissingPluginException catch (error) {
      _nativeAvailable = false;
      _logNativeUnavailable(operation, error);
      return fallback;
    } on PlatformException catch (error) {
      _nativeAvailable = false;
      _logNativeUnavailable(
        operation,
        '${error.code}${error.message == null ? '' : ': ${error.message}'}',
      );
      return fallback;
    }
  }

  void _logNativeUnavailable(String operation, Object error) {
    if (!kDebugMode) {
      return;
    }
    debugPrint(
      '[GO_PLAY-PiP] native channel disabled op=$operation error=$error',
    );
  }
}
