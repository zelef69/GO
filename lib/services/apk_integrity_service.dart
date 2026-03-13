import 'dart:io';

import 'package:crypto/crypto.dart';

class ApkIntegrityService {
  Future<String> sha256OfFile(File file) async {
    if (!file.existsSync()) {
      throw const ApkIntegrityException('ไม่พบไฟล์ APK สำหรับตรวจสอบ');
    }
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase();
  }

  Future<bool> verifySha256({
    required File file,
    required String expectedSha256,
  }) async {
    final normalizedExpected = expectedSha256.trim().toLowerCase();
    if (normalizedExpected.isEmpty) {
      throw const ApkIntegrityException('ค่า SHA-256 ที่คาดหวังไม่ถูกต้อง');
    }
    final actual = await sha256OfFile(file);
    return actual == normalizedExpected;
  }
}

class ApkIntegrityException implements Exception {
  const ApkIntegrityException(this.message);

  final String message;

  @override
  String toString() => message;
}
