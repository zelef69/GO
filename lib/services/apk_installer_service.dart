import 'dart:io';

import 'package:flutter/services.dart';

import '../shared/constants/channel_constants.dart';

class ApkInstallerService {
  ApkInstallerService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(ChannelConstants.update);

  final MethodChannel _channel;

  Future<bool> canInstallPackages() async {
    _ensureAndroid();
    final result = await _channel.invokeMethod<bool>(
      ChannelConstants.methodCanInstallPackages,
    );
    return result == true;
  }

  Future<void> openUnknownAppsSettings() async {
    _ensureAndroid();
    await _channel.invokeMethod<void>(
      ChannelConstants.methodOpenUnknownAppsSettings,
    );
  }

  Future<void> installApk(String apkPath) async {
    _ensureAndroid();
    final normalizedPath = apkPath.trim();
    if (normalizedPath.isEmpty) {
      throw const ApkInstallerException('ไม่พบไฟล์ APK สำหรับติดตั้ง');
    }
    await _channel.invokeMethod<void>(
      ChannelConstants.methodInstallApk,
      <String, dynamic>{'apkPath': normalizedPath},
    );
  }

  void _ensureAndroid() {
    if (!Platform.isAndroid) {
      throw const ApkInstallerException('รองรับเฉพาะ Android');
    }
  }
}

class ApkInstallerException implements Exception {
  const ApkInstallerException(this.message);

  final String message;

  @override
  String toString() => message;
}
