import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class ApkDownloadService {
  ApkDownloadService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<File> resolveTargetFile({
    required int versionCode,
    required String versionName,
  }) async {
    final baseDir = await getApplicationDocumentsDirectory();
    final updatesDir = Directory(
      '${baseDir.path}${Platform.pathSeparator}updates',
    );
    if (!updatesDir.existsSync()) {
      updatesDir.createSync(recursive: true);
    }
    final safeVersion = versionName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return File(
      '${updatesDir.path}${Platform.pathSeparator}go_play_${safeVersion}_$versionCode.apk',
    );
  }

  Future<File> downloadApk({
    required String apkUrl,
    required File targetFile,
    void Function(double progress)? onProgress,
  }) async {
    final tempFile = File('${targetFile.path}.part');
    if (tempFile.existsSync()) {
      tempFile.deleteSync();
    }
    if (!targetFile.parent.existsSync()) {
      targetFile.parent.createSync(recursive: true);
    }

    try {
      await _dio.download(
        apkUrl,
        tempFile.path,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          if (onProgress == null || total <= 0) {
            return;
          }
          final progress = (received / total).clamp(0.0, 1.0);
          onProgress(progress);
        },
      );
    } on DioException catch (error) {
      final detail = error.message?.trim();
      throw ApkDownloadException(
        detail == null || detail.isEmpty
            ? 'ดาวน์โหลดไฟล์อัปเดตไม่สำเร็จ'
            : 'ดาวน์โหลดไฟล์อัปเดตไม่สำเร็จ: $detail',
      );
    } catch (_) {
      throw const ApkDownloadException('ดาวน์โหลดไฟล์อัปเดตไม่สำเร็จ');
    }

    if (!tempFile.existsSync()) {
      throw const ApkDownloadException('ไม่พบไฟล์ APK ที่ดาวน์โหลด');
    }

    if (targetFile.existsSync()) {
      targetFile.deleteSync();
    }
    return tempFile.rename(targetFile.path);
  }
}

class ApkDownloadException implements Exception {
  const ApkDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}
