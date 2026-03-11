import '../../shared/constants/channel_constants.dart';
import '../../shared/platform/method_channel_client.dart';
import 'package:flutter/services.dart';

class PiPChannel {
  PiPChannel() : _channelClient = MethodChannelClient(ChannelConstants.pip);

  final MethodChannelClient _channelClient;

  Future<void> setPiPEnabled(bool enabled) async {
    await _channelClient.invokeMethod<void>(
      ChannelConstants.methodSetPiPEnabled,
      <String, dynamic>{'enabled': enabled},
    );
  }

  Future<void> setBackgroundPlaybackEnabled(bool enabled) async {
    await _channelClient.invokeMethod<void>(
      ChannelConstants.methodSetBackgroundPlaybackEnabled,
      <String, dynamic>{'enabled': enabled},
    );
  }

  Future<void> setAppInForeground(bool inForeground) async {
    await _channelClient.invokeMethod<void>(
      ChannelConstants.methodSetAppInForeground,
      <String, dynamic>{'inForeground': inForeground},
    );
  }

  Future<void> setVideoState({
    required bool isPlaying,
    required bool isFullscreen,
    required int videoWidth,
    required int videoHeight,
    int videoRectLeft = 0,
    int videoRectTop = 0,
    int videoRectRight = 0,
    int videoRectBottom = 0,
    String title = '',
    String author = '',
    int durationMs = 0,
    int positionMs = 0,
    bool hasNext = false,
  }) async {
    await _channelClient.invokeMethod<void>(
      ChannelConstants.methodSetVideoState,
      <String, dynamic>{
        'isPlaying': isPlaying,
        'isFullscreen': isFullscreen,
        'videoWidth': videoWidth,
        'videoHeight': videoHeight,
        'videoRectLeft': videoRectLeft,
        'videoRectTop': videoRectTop,
        'videoRectRight': videoRectRight,
        'videoRectBottom': videoRectBottom,
        'title': title,
        'author': author,
        'durationMs': durationMs,
        'positionMs': positionMs,
        'hasNext': hasNext,
      },
    );
  }

  Future<bool> enterPiPIfEligible() async {
    return await _channelClient.invokeMethod<bool>(
          ChannelConstants.methodEnterPiPIfEligible,
        ) ??
        false;
  }

  Future<bool> isPiPSupported() async {
    return await _channelClient.invokeMethod<bool>(
          ChannelConstants.methodIsPiPSupported,
        ) ??
        false;
  }

  Future<bool> isInPiPMode() async {
    return await _channelClient.invokeMethod<bool>(
          ChannelConstants.methodIsInPiPMode,
        ) ??
        false;
  }

  void setMethodCallHandler(
    Future<dynamic> Function(MethodCall call)? handler,
  ) {
    _channelClient.setMethodCallHandler(handler);
  }
}
