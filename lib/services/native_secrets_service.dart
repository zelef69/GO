import 'package:flutter/services.dart';

import '../shared/constants/channel_constants.dart';

class NativeSecrets {
  const NativeSecrets({
    required this.pinSetId,
    required this.certificatePinsSha256,
    required this.expectedAppId,
  });

  final String pinSetId;
  final List<String> certificatePinsSha256;
  final String expectedAppId;
}

/// Reads sensitive values from native layer so Dart does not embed
/// certificate pins, signature hashes, or environment security constants.
class NativeSecretsService {
  NativeSecretsService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(ChannelConstants.security);

  final MethodChannel _channel;

  Future<NativeSecrets> loadNativeSecrets() async {
    final raw = await _channel.invokeMapMethod<Object?, Object?>(
      ChannelConstants.methodGetNativeSecrets,
    );
    final pinSetId = (raw?['pinSetId'] ?? 'unknown').toString();
    final expectedAppId = (raw?['expectedAppId'] ?? '').toString();
    final pinsRaw = raw?['certificatePinsSha256'];
    final pins = pinsRaw is List
        ? pinsRaw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : const <String>[];
    return NativeSecrets(
      pinSetId: pinSetId,
      certificatePinsSha256: pins,
      expectedAppId: expectedAppId,
    );
  }
}
