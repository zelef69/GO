import 'package:flutter/services.dart';

import 'pip_channel.dart';
import 'pip_video_state.dart';

class PiPController {
  PiPController({required PiPChannel channel}) : _channel = channel;

  final PiPChannel _channel;

  PiPVideoState _state = PiPVideoState.empty();
  bool _pipEnabled = true;
  bool _isInPiPMode = false;

  PiPVideoState get state => _state;
  bool get isInPiPMode => _isInPiPMode;

  Future<void> initialize({required bool pipEnabled}) async {
    _pipEnabled = pipEnabled;
    await _channel.setPiPEnabled(pipEnabled);
    await _sendStateToNative();
  }

  Future<void> setPiPEnabled(bool enabled) async {
    _pipEnabled = enabled;
    await _channel.setPiPEnabled(enabled);
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
    return _channel.enterPiPIfEligible();
  }

  Future<bool> refreshPiPModeFromNative() async {
    final nativeInPiP = await _channel.isInPiPMode();
    _isInPiPMode = nativeInPiP;
    return nativeInPiP;
  }

  Future<void> _sendStateToNative() async {
    await _channel.setVideoState(
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
    );
  }
}
