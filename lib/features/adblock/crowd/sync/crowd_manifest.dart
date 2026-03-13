import '../models/learned_signature.dart';

class CrowdSignatureManifest {
  const CrowdSignatureManifest({
    required this.upToDate,
    required this.version,
    required this.checksum,
    required this.storagePath,
    required this.downloadUrl,
    required this.createdAtMs,
    required this.signatureCount,
  });

  const CrowdSignatureManifest.upToDate()
    : upToDate = true,
      version = 0,
      checksum = '',
      storagePath = '',
      downloadUrl = '',
      createdAtMs = 0,
      signatureCount = 0;

  final bool upToDate;
  final int version;
  final String checksum;
  final String storagePath;
  final String downloadUrl;
  final int createdAtMs;
  final int signatureCount;

  bool get hasDownload => downloadUrl.isNotEmpty;

  factory CrowdSignatureManifest.fromMap(Map<String, dynamic> map) {
    return CrowdSignatureManifest(
      upToDate: map['upToDate'] == true,
      version: _toInt(map['version']),
      checksum: (map['checksum'] ?? '').toString().trim(),
      storagePath: (map['storagePath'] ?? '').toString().trim(),
      downloadUrl: (map['downloadUrl'] ?? '').toString().trim(),
      createdAtMs: _toInt(map['createdAtMs']),
      signatureCount: _toInt(map['signatureCount']),
    );
  }

  static int _toInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim()) ?? 0;
    }
    return 0;
  }
}

class CrowdSignatureSnapshot {
  const CrowdSignatureSnapshot({
    required this.version,
    required this.checksum,
    required this.createdAtMs,
    required this.signatures,
  });

  final int version;
  final String checksum;
  final int createdAtMs;
  final List<LearnedSignature> signatures;

  factory CrowdSignatureSnapshot.fromMap(Map<String, dynamic> map) {
    final rawSignatures = map['signatures'];
    final signatures = <LearnedSignature>[];
    if (rawSignatures is List) {
      for (final entry in rawSignatures) {
        if (entry is Map<String, dynamic>) {
          final signature = LearnedSignature.fromSnapshotMap(entry);
          if (signature.sigHash.isNotEmpty) {
            signatures.add(signature);
          }
        } else if (entry is Map) {
          final converted = entry.map(
            (key, value) => MapEntry(key.toString(), value),
          );
          final signature = LearnedSignature.fromSnapshotMap(converted);
          if (signature.sigHash.isNotEmpty) {
            signatures.add(signature);
          }
        }
      }
    }
    return CrowdSignatureSnapshot(
      version: CrowdSignatureManifest._toInt(map['version']),
      checksum: (map['checksum'] ?? '').toString().trim(),
      createdAtMs: CrowdSignatureManifest._toInt(map['createdAtMs']),
      signatures: signatures,
    );
  }
}
