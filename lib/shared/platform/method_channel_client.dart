import 'package:flutter/services.dart';

class MethodChannelClient {
  MethodChannelClient(String channelName)
    : _channel = MethodChannel(channelName);

  final MethodChannel _channel;

  Future<T?> invokeMethod<T>(String method, [Map<String, dynamic>? arguments]) {
    return _channel.invokeMethod<T>(method, arguments);
  }

  void setMethodCallHandler(
    Future<dynamic> Function(MethodCall call)? handler,
  ) {
    _channel.setMethodCallHandler(handler);
  }
}
