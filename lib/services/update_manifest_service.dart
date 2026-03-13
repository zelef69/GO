import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';

import '../models/update_manifest.dart';

enum UpdateManifestSource { auto, manifestUrl, firestore }

class UpdateManifestService {
  UpdateManifestService({
    required String manifestUrl,
    required UpdateManifestSource source,
    required String firestoreCollection,
    required String firestoreDocument,
    required String defaultAppId,
    Dio? dio,
    FirebaseFirestore? firestore,
  }) : _manifestUrl = manifestUrl.trim(),
       _source = source,
       _firestoreCollection = firestoreCollection.trim(),
       _firestoreDocument = firestoreDocument.trim(),
       _defaultAppId = defaultAppId.trim(),
       _dio = dio ?? Dio(),
       _firestore = firestore ?? FirebaseFirestore.instance;

  final String _manifestUrl;
  final UpdateManifestSource _source;
  final String _firestoreCollection;
  final String _firestoreDocument;
  final String _defaultAppId;
  final Dio _dio;
  final FirebaseFirestore _firestore;

  Future<UpdateManifest> fetchManifest() async {
    if (_source == UpdateManifestSource.manifestUrl) {
      return _fetchFromManifestUrl();
    }
    if (_source == UpdateManifestSource.firestore) {
      return _fetchFromFirestore();
    }

    try {
      if (_manifestUrl.isNotEmpty) {
        return await _fetchFromManifestUrl();
      }
    } catch (_) {
      if (_firestoreCollection.isEmpty || _firestoreDocument.isEmpty) {
        rethrow;
      }
    }
    return _fetchFromFirestore();
  }

  Future<UpdateManifest> _fetchFromManifestUrl() async {
    if (_manifestUrl.isEmpty) {
      throw const UpdateManifestException('ยังไม่ได้ตั้งค่า manifest URL');
    }

    final uri = Uri.tryParse(_manifestUrl);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw const UpdateManifestException('manifest URL ไม่ถูกต้อง');
    }

    Response<dynamic> response;
    try {
      response = await _dio.get<dynamic>(_manifestUrl);
    } on DioException catch (error) {
      final detail = error.message?.trim();
      throw UpdateManifestException(
        detail == null || detail.isEmpty
            ? 'โหลด manifest ไม่สำเร็จ'
            : 'โหลด manifest ไม่สำเร็จ: $detail',
      );
    } catch (_) {
      throw const UpdateManifestException('โหลด manifest ไม่สำเร็จ');
    }

    final data = response.data;
    if (data is! Map) {
      throw const UpdateManifestException('manifest JSON ไม่ถูกต้อง');
    }

    try {
      return UpdateManifest.fromJson(
        data.map((key, value) => MapEntry(key.toString(), value)),
      );
    } on FormatException catch (error) {
      throw UpdateManifestException(error.message);
    } catch (_) {
      throw const UpdateManifestException('อ่านค่า manifest ไม่สำเร็จ');
    }
  }

  Future<UpdateManifest> _fetchFromFirestore() async {
    if (_firestoreCollection.isEmpty || _firestoreDocument.isEmpty) {
      throw const UpdateManifestException(
        'ยังไม่ได้ตั้งค่า Firestore collection/document สำหรับอัปเดต',
      );
    }

    DocumentSnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await _firestore
          .collection(_firestoreCollection)
          .doc(_firestoreDocument)
          .get();
    } catch (error) {
      throw UpdateManifestException(
        'อ่านค่าอัปเดตจาก Firestore ไม่สำเร็จ: ${error.toString()}',
      );
    }

    if (!snapshot.exists) {
      throw UpdateManifestException(
        'ไม่พบเอกสารอัปเดตใน Firestore ($_firestoreCollection/$_firestoreDocument)',
      );
    }
    final data = snapshot.data();
    if (data == null || data.isEmpty) {
      throw const UpdateManifestException(
        'เอกสารอัปเดตใน Firestore ไม่มีข้อมูล',
      );
    }

    final normalized = _normalizeFirestoreManifest(data);
    try {
      return UpdateManifest.fromJson(normalized);
    } on FormatException catch (error) {
      throw UpdateManifestException(
        'ข้อมูลอัปเดต Firestore ไม่ถูกต้อง: ${error.message}',
      );
    }
  }

  Map<String, dynamic> _normalizeFirestoreManifest(Map<String, dynamic> data) {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final changelogRaw = _pick(data, <String>['changelog']);
    final List<String> changelog;
    if (changelogRaw is List) {
      changelog = changelogRaw
          .map((entry) => entry.toString().trim())
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
    } else if (changelogRaw is String && changelogRaw.trim().isNotEmpty) {
      changelog = <String>[changelogRaw.trim()];
    } else {
      changelog = const <String>[];
    }

    return <String, dynamic>{
      'appId':
          _pickString(data, <String>[
            'appId',
            'applicationId',
            'packageName',
          ]) ??
          _defaultAppId,
      'channel': _pickString(data, <String>['channel']) ?? 'stable',
      'latestVersionCode':
          _pickInt(data, <String>[
            'latestVersionCode',
            'versionCode',
            'buildNumber',
          ]) ??
          0,
      'latestVersionName':
          _pickString(data, <String>[
            'latestVersionName',
            'versionName',
            'version',
          ]) ??
          '',
      'minSupportedVersionCode':
          _pickInt(data, <String>['minSupportedVersionCode']) ?? 0,
      'forceUpdate': _pickBool(data, <String>['forceUpdate']) ?? false,
      'apkUrl':
          _pickString(data, <String>[
            'apkUrl',
            'downloadUrl',
            'apkLink',
            'downloadLink',
          ]) ??
          '',
      'apkSha256': _pickString(data, <String>['apkSha256', 'sha256']) ?? '',
      'apkSizeBytes': _pickInt(data, <String>['apkSizeBytes']) ?? 0,
      'changelog': changelog,
      'publishedAt':
          _timestampToIsoString(_pick(data, <String>['publishedAt'])) ?? nowIso,
    };
  }

  dynamic _pick(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      if (data.containsKey(key)) {
        return data[key];
      }
    }
    return null;
  }

  String? _pickString(Map<String, dynamic> data, List<String> keys) {
    final value = _pick(data, keys);
    if (value == null) {
      return null;
    }
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  int? _pickInt(Map<String, dynamic> data, List<String> keys) {
    final value = _pick(data, keys);
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  bool? _pickBool(Map<String, dynamic> data, List<String> keys) {
    final value = _pick(data, keys);
    if (value is bool) {
      return value;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') {
        return true;
      }
      if (normalized == 'false' || normalized == '0') {
        return false;
      }
    }
    if (value is num) {
      return value != 0;
    }
    return null;
  }

  String? _timestampToIsoString(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is Timestamp) {
      return value.toDate().toUtc().toIso8601String();
    }
    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }
    final text = value.toString().trim();
    if (text.isEmpty) {
      return null;
    }
    return DateTime.tryParse(text)?.toUtc().toIso8601String();
  }
}

class UpdateManifestException implements Exception {
  const UpdateManifestException(this.message);

  final String message;

  @override
  String toString() => message;
}
