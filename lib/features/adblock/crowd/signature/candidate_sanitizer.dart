import 'dart:convert';

import 'package:crypto/crypto.dart';

class CrowdSanitizedCandidate {
  const CrowdSanitizedCandidate({
    required this.sigHash,
    required this.resourceType,
    required this.hostPattern,
    required this.pathPattern,
    required this.sourceHost,
    required this.markerKeys,
    required this.requireAdSignal,
    required this.baseReason,
    required this.confidence,
    required this.score,
    required this.createdAtMs,
  });

  final String sigHash;
  final String resourceType;
  final String hostPattern;
  final String pathPattern;
  final String sourceHost;
  final List<String> markerKeys;
  final bool requireAdSignal;
  final String baseReason;
  final double confidence;
  final double score;
  final int createdAtMs;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'sigHash': sigHash,
      'resourceType': resourceType,
      'hostPattern': hostPattern,
      'pathPattern': pathPattern,
      'sourceHost': sourceHost,
      'markerKeys': markerKeys,
      'requireAdSignal': requireAdSignal,
      'baseReason': baseReason,
      'confidence': confidence,
      'score': score,
      'createdAtMs': createdAtMs,
    };
  }

  factory CrowdSanitizedCandidate.fromMap(Map<String, dynamic> map) {
    final rawMarkerKeys = map['markerKeys'];
    final markerKeys = <String>[];
    if (rawMarkerKeys is List) {
      for (final key in rawMarkerKeys) {
        final normalized = key.toString().trim().toLowerCase();
        if (normalized.isNotEmpty && !markerKeys.contains(normalized)) {
          markerKeys.add(normalized);
        }
      }
    }
    markerKeys.sort();

    return CrowdSanitizedCandidate(
      sigHash: (map['sigHash'] ?? '').toString().trim(),
      resourceType: (map['resourceType'] ?? '').toString().trim().toLowerCase(),
      hostPattern: (map['hostPattern'] ?? '').toString().trim().toLowerCase(),
      pathPattern: (map['pathPattern'] ?? '').toString().trim().toLowerCase(),
      sourceHost: (map['sourceHost'] ?? '').toString().trim().toLowerCase(),
      markerKeys: markerKeys,
      requireAdSignal: map['requireAdSignal'] == true,
      baseReason: (map['baseReason'] ?? '').toString().trim().toLowerCase(),
      confidence: _toDouble(map['confidence']),
      score: _toDouble(map['score']),
      createdAtMs: _toInt(map['createdAtMs']),
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.trim()) ?? 0;
    }
    return 0;
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

class CrowdCandidateSanitizer {
  const CrowdCandidateSanitizer();

  static const Set<String> _highConfidenceLearningReasons = <String>{
    'googlevideo_ad_query_hard',
    'pagead_interaction_guard',
    'heuristic_matcher',
    'engine_match',
    'third_party_tracker',
  };

  static const Set<String> _markerAllowlist = <String>{
    'oad',
    'ads_payload',
    'adformat',
    'ad_type',
    'ad_preroll',
    'dclk_video_ads',
    'ad3_module',
    'videoadid',
    'adtag',
    'ad_tag',
    'ad_debug',
    'adsid',
    'ad_host_tier',
    'ad_flags',
    'ad_cpn',
    'adid',
    'ad_mt',
    'ad_eurl',
    'ad_url',
    'adurl',
    'ad_break',
    'ad_break_id',
    'adpod',
    'ad_pod',
    'ad_campaign',
    'ad_cid',
    'ad_placement',
    'adplacement',
    'ad_source',
    'adserver',
    'ad_server',
    'ad_slot',
    'adslot',
    'adslotname',
    'adcontext',
    'ad_context',
    'adcontexturl',
    'ad_context_url',
    'adunit',
    'ad_unit',
    'preroll',
    'midroll',
    'postroll',
    'label',
    'ctier',
    'ai',
    'cid',
    'sigh',
    'adk',
  };

  bool shouldLearnReason(String reason) {
    return _highConfidenceLearningReasons.contains(reason.trim().toLowerCase());
  }

  CrowdSanitizedCandidate? sanitize({
    required Uri uri,
    required String resourceType,
    required Uri? sourceUrl,
    required bool adShowing,
    required String reason,
    required int nowMs,
  }) {
    final normalizedReason = reason.trim().toLowerCase();
    if (!shouldLearnReason(normalizedReason)) {
      return null;
    }
    if (uri.scheme.toLowerCase() != 'https') {
      return null;
    }
    final normalizedResourceType = resourceType.trim().toLowerCase();
    if (normalizedResourceType.isEmpty) {
      return null;
    }

    final hostPattern = _normalizeHostPattern(uri.host);
    if (hostPattern.isEmpty) {
      return null;
    }
    final pathPattern = _normalizePathPattern(uri.path);
    final sourceHost = _normalizeSourceHost(sourceUrl?.host ?? '');
    final markerKeys = _extractMarkerKeys(uri.queryParameters.keys);
    if (markerKeys.isEmpty) {
      return null;
    }

    final requireAdSignal = _reasonRequiresAdSignal(normalizedReason);
    final confidence = _baseConfidence(normalizedReason, markerKeys.length);
    final score = confidence * 100;

    final canonical = jsonEncode(<String, dynamic>{
      'resourceType': normalizedResourceType,
      'hostPattern': hostPattern,
      'pathPattern': pathPattern,
      'sourceHost': sourceHost,
      'markerKeys': markerKeys,
      'requireAdSignal': requireAdSignal,
      'reason': normalizedReason,
    });
    final sigHash = sha256.convert(utf8.encode(canonical)).toString();

    return CrowdSanitizedCandidate(
      sigHash: sigHash,
      resourceType: normalizedResourceType,
      hostPattern: hostPattern,
      pathPattern: pathPattern,
      sourceHost: sourceHost,
      markerKeys: markerKeys,
      requireAdSignal: requireAdSignal,
      baseReason: normalizedReason,
      confidence: confidence,
      score: score,
      createdAtMs: nowMs,
    );
  }

  String _normalizeHostPattern(String host) {
    final normalized = host.trim().toLowerCase();
    if (normalized.isEmpty) {
      return '';
    }
    if (normalized == 'googlevideo.com' ||
        normalized.endsWith('.googlevideo.com')) {
      return '*.googlevideo.com';
    }
    if (normalized == 'youtube.com' || normalized.endsWith('.youtube.com')) {
      return '*.youtube.com';
    }
    if (normalized == 'doubleclick.net' ||
        normalized.endsWith('.doubleclick.net')) {
      return '*.doubleclick.net';
    }
    return normalized;
  }

  String _normalizePathPattern(String path) {
    final normalized = path.trim().toLowerCase();
    if (normalized.isEmpty) {
      return '/';
    }
    if (normalized.length > 180) {
      return normalized.substring(0, 180);
    }
    return normalized;
  }

  String _normalizeSourceHost(String sourceHost) {
    final normalized = sourceHost.trim().toLowerCase();
    if (normalized.isEmpty) {
      return '';
    }
    if (normalized == 'youtube.com' || normalized.endsWith('.youtube.com')) {
      return '*.youtube.com';
    }
    return normalized;
  }

  List<String> _extractMarkerKeys(Iterable<String> rawKeys) {
    final keys = <String>{};
    for (final rawKey in rawKeys) {
      final key = rawKey.trim().toLowerCase();
      if (key.isEmpty) {
        continue;
      }
      if (_markerAllowlist.contains(key) ||
          (key.startsWith('ad') && key.length <= 36)) {
        keys.add(key);
      }
    }
    final output = keys.toList(growable: false)..sort();
    if (output.length > 24) {
      return output.take(24).toList(growable: false);
    }
    return output;
  }

  bool _reasonRequiresAdSignal(String reason) {
    if (reason == 'pagead_interaction_guard' ||
        reason == 'googlevideo_ad_query_hard') {
      return false;
    }
    return true;
  }

  double _baseConfidence(String reason, int markerCount) {
    final markerBoost = markerCount >= 6
        ? 0.06
        : markerCount >= 3
        ? 0.03
        : 0;
    final base = switch (reason) {
      'googlevideo_ad_query_hard' => 0.96,
      'pagead_interaction_guard' => 0.95,
      'heuristic_matcher' => 0.90,
      'engine_match' => 0.86,
      'third_party_tracker' => 0.82,
      _ => 0.78,
    };
    final boosted = base + markerBoost;
    if (boosted > 0.99) {
      return 0.99;
    }
    return boosted;
  }
}
