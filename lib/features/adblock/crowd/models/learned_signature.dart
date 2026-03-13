class LearnedSignature {
  const LearnedSignature({
    required this.sigHash,
    required this.hostPattern,
    required this.pathPattern,
    required this.resourceType,
    required this.sourceHost,
    required this.markerKeys,
    required this.requireAdSignal,
    required this.state,
    required this.source,
    required this.score,
    required this.confidence,
    required this.seenCount,
    required this.falsePositiveCount,
    required this.firstSeenAtMs,
    required this.lastSeenAtMs,
    required this.updatedAtMs,
    this.expireAtMs,
    this.lastReason,
  });

  final String sigHash;
  final String hostPattern;
  final String pathPattern;
  final String resourceType;
  final String sourceHost;
  final List<String> markerKeys;
  final bool requireAdSignal;
  final String state;
  final String source;
  final double score;
  final double confidence;
  final int seenCount;
  final int falsePositiveCount;
  final int firstSeenAtMs;
  final int lastSeenAtMs;
  final int? expireAtMs;
  final int updatedAtMs;
  final String? lastReason;

  bool isActiveAt(int nowMs) {
    if (state != LearnedSignatureState.active) {
      return false;
    }
    if (expireAtMs == null) {
      return true;
    }
    return expireAtMs! > nowMs;
  }

  LearnedSignature copyWith({
    String? sigHash,
    String? hostPattern,
    String? pathPattern,
    String? resourceType,
    String? sourceHost,
    List<String>? markerKeys,
    bool? requireAdSignal,
    String? state,
    String? source,
    double? score,
    double? confidence,
    int? seenCount,
    int? falsePositiveCount,
    int? firstSeenAtMs,
    int? lastSeenAtMs,
    int? expireAtMs,
    bool clearExpireAtMs = false,
    int? updatedAtMs,
    String? lastReason,
    bool clearLastReason = false,
  }) {
    return LearnedSignature(
      sigHash: sigHash ?? this.sigHash,
      hostPattern: hostPattern ?? this.hostPattern,
      pathPattern: pathPattern ?? this.pathPattern,
      resourceType: resourceType ?? this.resourceType,
      sourceHost: sourceHost ?? this.sourceHost,
      markerKeys: markerKeys ?? this.markerKeys,
      requireAdSignal: requireAdSignal ?? this.requireAdSignal,
      state: state ?? this.state,
      source: source ?? this.source,
      score: score ?? this.score,
      confidence: confidence ?? this.confidence,
      seenCount: seenCount ?? this.seenCount,
      falsePositiveCount: falsePositiveCount ?? this.falsePositiveCount,
      firstSeenAtMs: firstSeenAtMs ?? this.firstSeenAtMs,
      lastSeenAtMs: lastSeenAtMs ?? this.lastSeenAtMs,
      expireAtMs: clearExpireAtMs ? null : (expireAtMs ?? this.expireAtMs),
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      lastReason: clearLastReason ? null : (lastReason ?? this.lastReason),
    );
  }

  Map<String, dynamic> toDbMap() {
    return <String, dynamic>{
      'sig_hash': sigHash,
      'host_pattern': hostPattern,
      'path_pattern': pathPattern,
      'resource_type': resourceType,
      'source_host': sourceHost,
      'marker_keys': markerKeys.join(','),
      'require_ad_signal': requireAdSignal ? 1 : 0,
      'state': state,
      'source': source,
      'score': score,
      'confidence': confidence,
      'seen_count': seenCount,
      'false_positive_count': falsePositiveCount,
      'first_seen_at': firstSeenAtMs,
      'last_seen_at': lastSeenAtMs,
      'expire_at': expireAtMs,
      'updated_at': updatedAtMs,
      'last_reason': lastReason,
    };
  }

  Map<String, dynamic> toSnapshotMap() {
    return <String, dynamic>{
      'sigHash': sigHash,
      'hostPattern': hostPattern,
      'pathPattern': pathPattern,
      'resourceType': resourceType,
      'sourceHost': sourceHost,
      'markerKeys': markerKeys,
      'requireAdSignal': requireAdSignal,
      'state': state,
      'source': source,
      'score': score,
      'confidence': confidence,
      'seenCount': seenCount,
      'falsePositiveCount': falsePositiveCount,
      'firstSeenAtMs': firstSeenAtMs,
      'lastSeenAtMs': lastSeenAtMs,
      'expireAtMs': expireAtMs,
      'updatedAtMs': updatedAtMs,
      'lastReason': lastReason,
    };
  }

  factory LearnedSignature.fromDbMap(Map<String, Object?> map) {
    return LearnedSignature(
      sigHash: (map['sig_hash'] ?? '').toString(),
      hostPattern: (map['host_pattern'] ?? '').toString(),
      pathPattern: (map['path_pattern'] ?? '').toString(),
      resourceType: (map['resource_type'] ?? '').toString(),
      sourceHost: (map['source_host'] ?? '').toString(),
      markerKeys: _decodeMarkerKeys(map['marker_keys']),
      requireAdSignal: (map['require_ad_signal'] as num?)?.toInt() == 1,
      state: (map['state'] ?? LearnedSignatureState.learning).toString(),
      source: (map['source'] ?? LearnedSignatureSource.local).toString(),
      score: _toDouble(map['score']),
      confidence: _toDouble(map['confidence']),
      seenCount: _toInt(map['seen_count']),
      falsePositiveCount: _toInt(map['false_positive_count']),
      firstSeenAtMs: _toInt(map['first_seen_at']),
      lastSeenAtMs: _toInt(map['last_seen_at']),
      expireAtMs: _toNullableInt(map['expire_at']),
      updatedAtMs: _toInt(map['updated_at']),
      lastReason: map['last_reason']?.toString(),
    );
  }

  factory LearnedSignature.fromSnapshotMap(Map<String, dynamic> map) {
    return LearnedSignature(
      sigHash: (map['sigHash'] ?? '').toString(),
      hostPattern: (map['hostPattern'] ?? '').toString(),
      pathPattern: (map['pathPattern'] ?? '').toString(),
      resourceType: (map['resourceType'] ?? '').toString(),
      sourceHost: (map['sourceHost'] ?? '').toString(),
      markerKeys: _decodeMarkerKeys(map['markerKeys']),
      requireAdSignal: map['requireAdSignal'] == true,
      state: (map['state'] ?? LearnedSignatureState.active).toString(),
      source: (map['source'] ?? LearnedSignatureSource.cloud).toString(),
      score: _toDouble(map['score']),
      confidence: _toDouble(map['confidence']),
      seenCount: _toInt(map['seenCount']),
      falsePositiveCount: _toInt(map['falsePositiveCount']),
      firstSeenAtMs: _toInt(map['firstSeenAtMs']),
      lastSeenAtMs: _toInt(map['lastSeenAtMs']),
      expireAtMs: _toNullableInt(map['expireAtMs']),
      updatedAtMs: _toInt(map['updatedAtMs']),
      lastReason: map['lastReason']?.toString(),
    );
  }

  static List<String> _decodeMarkerKeys(dynamic raw) {
    if (raw is List) {
      final keys =
          raw
              .map((entry) => entry.toString().trim().toLowerCase())
              .where((entry) => entry.isNotEmpty)
              .toSet()
              .toList(growable: false)
            ..sort();
      return keys;
    }
    final source = (raw ?? '').toString().trim();
    if (source.isEmpty) {
      return const <String>[];
    }
    final keys =
        source
            .split(',')
            .map((entry) => entry.trim().toLowerCase())
            .where((entry) => entry.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    return keys;
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

  static int? _toNullableInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }
}

class LearnedSignatureState {
  const LearnedSignatureState._();

  static const String learning = 'learning';
  static const String active = 'active';
  static const String quarantined = 'quarantined';
  static const String expired = 'expired';
}

class LearnedSignatureSource {
  const LearnedSignatureSource._();

  static const String local = 'local';
  static const String cloud = 'cloud';
}
