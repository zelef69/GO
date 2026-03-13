import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/models/device_identity.dart';

class DeviceIdService {
  DeviceIdService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _deviceIdKey = 'go_play_device_id_v1';
  final FlutterSecureStorage _storage;
  final Random _random = Random.secure();

  Future<DeviceIdentity> getIdentity() async {
    final deviceId = await _getOrCreateDeviceId();
    final platform = _platformLabel();
    return DeviceIdentity(
      deviceId: deviceId,
      deviceName: 'go_play_$platform',
      platform: platform,
      model: platform,
      appVersion: const String.fromEnvironment(
        'GO_PLAY_APP_VERSION',
        defaultValue: 'unknown',
      ),
    );
  }

  Future<String> _getOrCreateDeviceId() async {
    final existing = (await _storage.read(key: _deviceIdKey) ?? '').trim();
    if (existing.isNotEmpty) {
      return existing;
    }
    final generated = _generateDeviceId();
    await _storage.write(key: _deviceIdKey, value: generated);
    return generated;
  }

  String _generateDeviceId() {
    final bytes = List<int>.generate(24, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String _platformLabel() {
    if (kIsWeb) {
      return 'web';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }
}
