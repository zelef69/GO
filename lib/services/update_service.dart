import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/update_manifest.dart';
import 'apk_download_service.dart';
import 'apk_installer_service.dart';
import 'apk_integrity_service.dart';
import 'update_manifest_service.dart';

enum UpdateFlowState {
  checking,
  updateAvailable,
  downloading,
  downloaded,
  verifying,
  readyToInstall,
  installing,
  noUpdate,
  error,
}

class UpdateService extends ChangeNotifier {
  UpdateService({
    required UpdateManifestService manifestService,
    required ApkDownloadService apkDownloadService,
    required ApkIntegrityService apkIntegrityService,
    required ApkInstallerService apkInstallerService,
  }) : _manifestService = manifestService,
       _apkDownloadService = apkDownloadService,
       _apkIntegrityService = apkIntegrityService,
       _apkInstallerService = apkInstallerService;

  final UpdateManifestService _manifestService;
  final ApkDownloadService _apkDownloadService;
  final ApkIntegrityService _apkIntegrityService;
  final ApkInstallerService _apkInstallerService;

  UpdateFlowState _state = UpdateFlowState.noUpdate;
  double _downloadProgress = 0;
  String _message = '';
  String? _errorMessage;
  UpdateManifest? _manifest;
  int _currentVersionCode = 0;
  String _currentVersionName = 'unknown';
  String _currentPackageName = '';
  bool _isBusy = false;
  bool _awaitingInstallPermission = false;
  File? _readyApkFile;

  UpdateFlowState get state => _state;
  double get downloadProgress => _downloadProgress;
  String get message => _message;
  String? get errorMessage => _errorMessage;
  UpdateManifest? get manifest => _manifest;
  int get currentVersionCode => _currentVersionCode;
  String get currentVersionName => _currentVersionName;
  bool get isBusy => _isBusy;
  bool get awaitingInstallPermission => _awaitingInstallPermission;

  Future<void> startUpdateFlow() async {
    if (_isBusy) {
      return;
    }
    _isBusy = true;
    try {
      await _loadInstalledVersionInfo();
      _setState(UpdateFlowState.checking, 'กำลังตรวจสอบอัปเดต...');

      final manifest = await _manifestOrThrow();
      if (_currentPackageName.isNotEmpty &&
          manifest.appId != _currentPackageName) {
        throw UpdateFlowException(
          'manifest appId ไม่ตรงกับแอปนี้ (${manifest.appId})',
        );
      }
      if (manifest.latestVersionCode <= _currentVersionCode) {
        _setState(UpdateFlowState.noUpdate, 'แอปของคุณเป็นเวอร์ชันล่าสุดแล้ว');
        return;
      }

      _setState(
        UpdateFlowState.updateAvailable,
        'พบเวอร์ชันใหม่ ${manifest.latestVersionName}',
      );

      final targetFile = await _apkDownloadService.resolveTargetFile(
        versionCode: manifest.latestVersionCode,
        versionName: manifest.latestVersionName,
      );

      if (await targetFile.exists()) {
        _setState(
          UpdateFlowState.verifying,
          'กำลังตรวจสอบไฟล์อัปเดตที่มีอยู่...',
        );
        final cachedOk = await _apkIntegrityService.verifySha256(
          file: targetFile,
          expectedSha256: manifest.apkSha256,
        );
        if (cachedOk) {
          _readyApkFile = targetFile;
          _setState(
            UpdateFlowState.readyToInstall,
            'พบไฟล์อัปเดตที่พร้อมติดตั้งแล้ว',
          );
          await _installReadyApkOrRequestPermission();
          return;
        }
        await targetFile.delete();
      }

      _downloadProgress = 0;
      _setState(UpdateFlowState.downloading, 'กำลังดาวน์โหลดอัปเดต...');
      final downloadedFile = await _apkDownloadService.downloadApk(
        apkUrl: manifest.apkUrl,
        targetFile: targetFile,
        onProgress: (progress) {
          _downloadProgress = progress;
          _message = 'กำลังดาวน์โหลด ${(progress * 100).toStringAsFixed(0)}%';
          notifyListeners();
        },
      );
      if (manifest.apkSizeBytes > 0 &&
          downloadedFile.lengthSync() != manifest.apkSizeBytes) {
        await downloadedFile.delete();
        throw const UpdateFlowException(
          'ขนาดไฟล์ APK ไม่ถูกต้อง กรุณาลองดาวน์โหลดใหม่',
        );
      }

      _setState(UpdateFlowState.downloaded, 'ดาวน์โหลดอัปเดตเสร็จแล้ว');
      _setState(UpdateFlowState.verifying, 'กำลังตรวจสอบความถูกต้องของไฟล์...');
      final verified = await _apkIntegrityService.verifySha256(
        file: downloadedFile,
        expectedSha256: manifest.apkSha256,
      );
      if (!verified) {
        await downloadedFile.delete();
        throw const UpdateFlowException(
          'ตรวจสอบไฟล์อัปเดตไม่ผ่าน (SHA-256 ไม่ตรง)',
        );
      }

      _readyApkFile = downloadedFile;
      _setState(UpdateFlowState.readyToInstall, 'ไฟล์อัปเดตพร้อมติดตั้ง');
      await _installReadyApkOrRequestPermission();
    } catch (error) {
      _setError(_readableError(error));
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> resumePendingInstallIfPossible() async {
    if (!_awaitingInstallPermission || _readyApkFile == null || _isBusy) {
      return;
    }
    _isBusy = true;
    try {
      final canInstall = await _apkInstallerService.canInstallPackages();
      if (!canInstall) {
        return;
      }
      _awaitingInstallPermission = false;
      await _installReadyApkOrRequestPermission();
    } catch (error) {
      _setError(_readableError(error));
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> refreshManifestOnly() async {
    if (_isBusy) {
      return;
    }
    try {
      await _loadInstalledVersionInfo();
      final manifest = await _manifestOrThrow();
      if (_currentPackageName.isNotEmpty &&
          manifest.appId != _currentPackageName) {
        throw UpdateFlowException(
          'manifest appId ไม่ตรงกับแอปนี้ (${manifest.appId})',
        );
      }
      if (manifest.latestVersionCode > _currentVersionCode) {
        _setState(
          UpdateFlowState.updateAvailable,
          'พบเวอร์ชันใหม่ ${manifest.latestVersionName}',
        );
      } else {
        _setState(UpdateFlowState.noUpdate, 'แอปของคุณเป็นเวอร์ชันล่าสุดแล้ว');
      }
    } catch (error) {
      _setError(_readableError(error));
    }
  }

  Future<void> _installReadyApkOrRequestPermission() async {
    final apkFile = _readyApkFile;
    if (apkFile == null || !apkFile.existsSync()) {
      throw const UpdateFlowException('ไม่พบไฟล์ APK ที่พร้อมติดตั้ง');
    }

    final canInstall = await _apkInstallerService.canInstallPackages();
    if (!canInstall) {
      _awaitingInstallPermission = true;
      _setState(
        UpdateFlowState.readyToInstall,
        'กรุณาอนุญาตติดตั้งแอปจากแหล่งที่ไม่รู้จัก แล้วกลับมาแอปนี้',
      );
      await _apkInstallerService.openUnknownAppsSettings();
      return;
    }

    _awaitingInstallPermission = false;
    _setState(UpdateFlowState.installing, 'กำลังเปิดตัวติดตั้งแอป...');
    await _apkInstallerService.installApk(apkFile.path);
  }

  Future<UpdateManifest> _manifestOrThrow() async {
    final manifest = await _manifestService.fetchManifest();
    _manifest = manifest;
    return manifest;
  }

  Future<void> _loadInstalledVersionInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    _currentVersionName = packageInfo.version;
    _currentVersionCode = int.tryParse(packageInfo.buildNumber.trim()) ?? 0;
    _currentPackageName = packageInfo.packageName.trim();
  }

  void _setState(UpdateFlowState next, String message) {
    _state = next;
    _message = message;
    _errorMessage = null;
    if (next != UpdateFlowState.downloading) {
      _downloadProgress = 0;
    }
    notifyListeners();
  }

  void _setError(String message) {
    _state = UpdateFlowState.error;
    _message = message;
    _errorMessage = message;
    notifyListeners();
  }

  String _readableError(Object error) {
    if (error is UpdateFlowException) {
      return error.message;
    }
    if (error is UpdateManifestException) {
      return error.message;
    }
    if (error is ApkDownloadException) {
      return error.message;
    }
    if (error is ApkIntegrityException) {
      return error.message;
    }
    if (error is ApkInstallerException) {
      return error.message;
    }
    return 'อัปเดตแอปไม่สำเร็จ: ${error.toString()}';
  }
}

class UpdateFlowException implements Exception {
  const UpdateFlowException(this.message);

  final String message;

  @override
  String toString() => message;
}
