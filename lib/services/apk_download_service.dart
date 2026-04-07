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
    // Keep downloaded APKs under the app files/support directory so the
    // existing FileProvider `<files-path>` can share them with the installer.
    final baseDir = await getApplicationSupportDirectory();
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
    if (!targetFile.parent.existsSync()) {
      targetFile.parent.createSync(recursive: true);
    }

    try {
      if (tempFile.existsSync() && tempFile.lengthSync() > 0) {
        await _resumeDownload(
          apkUrl: apkUrl,
          tempFile: tempFile,
          onProgress: onProgress,
        );
      } else {
        await _downloadFresh(
          apkUrl: apkUrl,
          tempFile: tempFile,
          onProgress: onProgress,
        );
      }
    } on DioException catch (error) {
      final detail = error.message?.trim();
      throw ApkDownloadException(
        detail == null || detail.isEmpty
            ? 'ดาวน์โหลดไฟล์อัปเดตไม่สำเร็จ'
            : 'ดาวน์โหลดไฟล์อัปเดตไม่สำเร็จ: $detail',
      );
    } catch (error) {
      if (error is ApkDownloadException) {
        rethrow;
      }
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

  Future<void> _downloadFresh({
    required String apkUrl,
    required File tempFile,
    void Function(double progress)? onProgress,
  }) async {
    if (tempFile.existsSync()) {
      tempFile.deleteSync();
    }

    await _dio.download(
      apkUrl,
      tempFile.path,
      deleteOnError: false,
      onReceiveProgress: (received, total) {
        if (onProgress == null || total <= 0) {
          return;
        }
        final progress = (received / total).clamp(0.0, 1.0);
        onProgress(progress);
      },
    );
  }

  Future<void> _resumeDownload({
    required String apkUrl,
    required File tempFile,
    void Function(double progress)? onProgress,
  }) async {
    final existingBytes = tempFile.lengthSync();
    final response = await _dio.get<ResponseBody>(
      apkUrl,
      options: Options(
        responseType: ResponseType.stream,
        headers: <String, String>{
          HttpHeaders.rangeHeader: 'bytes=$existingBytes-',
        },
      ),
    );

    final statusCode = response.statusCode ?? 0;
    if (statusCode == HttpStatus.ok) {
      await _downloadFresh(
        apkUrl: apkUrl,
        tempFile: tempFile,
        onProgress: onProgress,
      );
      return;
    }

    if (statusCode != HttpStatus.partialContent) {
      throw ApkDownloadException(
        'resume download ไม่สำเร็จ (HTTP $statusCode)',
      );
    }

    final remainingLength =
        int.tryParse(
          response.headers.value(Headers.contentLengthHeader) ?? '',
        ) ??
        0;
    final totalBytes = existingBytes + remainingLength;
    var receivedBytes = existingBytes;

    final sink = tempFile.openWrite(mode: FileMode.append);
    try {
      await for (final chunk in response.data!.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (onProgress != null && totalBytes > 0) {
          final progress = (receivedBytes / totalBytes).clamp(0.0, 1.0);
          onProgress(progress);
        }
      }
    } finally {
      await sink.close();
    }
  }
}

class ApkDownloadException implements Exception {
  const ApkDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}
