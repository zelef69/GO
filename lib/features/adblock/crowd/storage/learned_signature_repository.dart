import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/learned_signature.dart';
import '../models/learned_signature_match_result.dart';
import '../signature/candidate_sanitizer.dart';
import '../signature/signature_matcher.dart';
import 'learned_signature_db.dart';

class LearnedCandidateEvent {
  const LearnedCandidateEvent({
    required this.id,
    required this.payload,
    required this.createdAtMs,
  });

  final int id;
  final CrowdSanitizedCandidate payload;
  final int createdAtMs;
}

class LearnedSignatureRepository {
  LearnedSignatureRepository({
    required LearnedSignatureDb database,
    required SignatureMatcher matcher,
    CrowdCandidateSanitizer? sanitizer,
    DateTime Function()? now,
    bool debugLoggingEnabled = false,
    void Function(String message)? logSink,
  }) : _database = database,
       _matcher = matcher,
       _sanitizer = sanitizer ?? const CrowdCandidateSanitizer(),
       _now = now ?? DateTime.now,
       _debugLoggingEnabled = debugLoggingEnabled,
       _logSink = logSink;

  final LearnedSignatureDb _database;
  final SignatureMatcher _matcher;
  final CrowdCandidateSanitizer _sanitizer;
  final DateTime Function() _now;
  final bool _debugLoggingEnabled;
  final void Function(String message)? _logSink;

  static const int _maxCrowdLearnLogs = 260;

  bool _initialized = false;
  bool _dbAvailable = false;
  bool _disposed = false;
  int _snapshotVersion = 0;
  String _snapshotChecksum = '';
  int _nextMemoryCandidateId = -1;
  int _suspiciousLinkTotal = 0;
  int _crowdLearnLogCount = 0;

  final Map<String, LearnedSignature> _signatures =
      <String, LearnedSignature>{};
  final Map<int, LearnedCandidateEvent> _memoryPendingEvents =
      <int, LearnedCandidateEvent>{};

  int get snapshotVersion => _snapshotVersion;
  String get snapshotChecksum => _snapshotChecksum;

  Future<void> initialize() async {
    if (_initialized || _disposed) {
      return;
    }
    final db = await _database.database;
    _dbAvailable = db != null;
    if (db != null) {
      await _loadAll(db);
    }
    _initialized = true;
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _initialized = false;
    _signatures.clear();
    _memoryPendingEvents.clear();
    _suspiciousLinkTotal = 0;
    _crowdLearnLogCount = 0;
    await _database.close();
  }

  LearnedSignatureMatchResult precheck({
    required Uri uri,
    required String resourceType,
    required Uri? sourceUrl,
    required bool adShowing,
    required bool playbackStalled,
  }) {
    if (!_initialized || _disposed) {
      return const LearnedSignatureMatchResult.noMatch();
    }
    final nowMs = _now().millisecondsSinceEpoch;
    return _matcher.match(
      signatures: _signatures.values,
      uri: uri,
      resourceType: resourceType,
      sourceUrl: sourceUrl,
      adShowing: adShowing,
      playbackStalled: playbackStalled,
      nowMs: nowMs,
    );
  }

  Future<void> recordDecision({
    required Uri uri,
    required String resourceType,
    required Uri? sourceUrl,
    required bool adShowing,
    required bool blocked,
    required String reason,
    String? matchedRule,
  }) async {
    if (!blocked || _disposed) {
      return;
    }
    await initialize();
    final nowMs = _now().millisecondsSinceEpoch;
    final candidate = _sanitizer.sanitize(
      uri: uri,
      resourceType: resourceType,
      sourceUrl: sourceUrl,
      adShowing: adShowing,
      reason: reason,
      nowMs: nowMs,
    );
    if (candidate == null) {
      return;
    }
    _suspiciousLinkTotal += 1;
    final signature = await _upsertFromCandidate(
      candidate,
      nowMs: nowMs,
      reason: reason,
    );
    _logSuspiciousLink(
      candidate: candidate,
      signature: signature,
      reason: reason,
      action: 'learn_candidate',
    );
    await _enqueueCandidate(candidate, nowMs: nowMs);
    if (matchedRule != null && matchedRule.trim().isNotEmpty) {
      await _setLastReason(candidate.sigHash, reason: reason, nowMs: nowMs);
    }
  }

  Future<void> recordPlaybackStall({
    required Uri uri,
    required String resourceType,
    required Uri? sourceUrl,
  }) async {
    if (_disposed) {
      return;
    }
    await initialize();
    if (_signatures.isEmpty) {
      return;
    }
    final nowMs = _now().millisecondsSinceEpoch;
    final match = _matcher.match(
      signatures: _signatures.values,
      uri: uri,
      resourceType: resourceType,
      sourceUrl: sourceUrl,
      adShowing: false,
      playbackStalled: false,
      nowMs: nowMs,
    );
    if (!match.matched) {
      return;
    }
    final current = _signatures[match.sigHash];
    if (current == null) {
      return;
    }

    final nextFalsePositiveCount = current.falsePositiveCount + 1;
    final nextScore = (current.score - 18).clamp(0, 100).toDouble();
    final nextConfidence = (current.confidence - 0.14).clamp(0, 1).toDouble();
    final nextState = nextFalsePositiveCount >= 3
        ? LearnedSignatureState.quarantined
        : current.state;
    final updated = current.copyWith(
      falsePositiveCount: nextFalsePositiveCount,
      score: nextScore,
      confidence: nextConfidence,
      state: nextState,
      updatedAtMs: nowMs,
      lastSeenAtMs: nowMs,
      lastReason: 'playback_stall_feedback',
    );
    _signatures[updated.sigHash] = updated;
    await _persistSignature(updated);
    _log(
      'stall_feedback total=$_suspiciousLinkTotal sig=${_shortSig(updated.sigHash)} status=${updated.state}/${_statusLevel(updated)} seen=${updated.seenCount} fp=${updated.falsePositiveCount} score=${updated.score.toStringAsFixed(1)} conf=${updated.confidence.toStringAsFixed(2)}',
    );
  }

  Future<void> recordPlaybackDebugSignal(
    Map<String, dynamic> payload, {
    Uri? pageUri,
  }) async {
    if (_disposed) {
      return;
    }
    final event = (payload['event'] ?? '').toString().trim().toLowerCase();
    if (event != 'video:waiting' && event != 'video:emptied') {
      return;
    }
    final adShowing = payload['adShowing'] == true;
    if (adShowing) {
      return;
    }
    final readyState = _toInt(payload['readyState']);
    if (readyState > 1) {
      return;
    }
    final rawUrl = (payload['url'] ?? '').toString().trim();
    final parsedUri = Uri.tryParse(rawUrl);
    final uri = parsedUri ?? pageUri;
    if (uri == null || uri.host.isEmpty) {
      return;
    }
    await recordPlaybackStall(
      uri: uri,
      resourceType: 'media',
      sourceUrl: pageUri,
    );
  }

  Future<List<LearnedCandidateEvent>> takePendingCandidates({
    int limit = 30,
  }) async {
    if (_disposed) {
      return const <LearnedCandidateEvent>[];
    }
    await initialize();
    final nowMs = _now().millisecondsSinceEpoch;
    if (_dbAvailable) {
      final db = await _database.database;
      if (db == null) {
        _dbAvailable = false;
      } else {
        final rows = await db.query(
          LearnedSignatureDb.candidateEventsTable,
          where: 'status = ? AND (next_retry_at IS NULL OR next_retry_at <= ?)',
          whereArgs: <Object?>['pending', nowMs],
          orderBy: 'created_at ASC',
          limit: limit,
        );
        return rows
            .map((row) {
              final id = _toInt(row['id']);
              if (id <= 0) {
                return null;
              }
              final payloadRaw = (row['payload'] ?? '').toString();
              final decoded = jsonDecode(payloadRaw);
              if (decoded is! Map<String, dynamic>) {
                return null;
              }
              final payload = CrowdSanitizedCandidate.fromMap(decoded);
              if (payload.sigHash.isEmpty) {
                return null;
              }
              return LearnedCandidateEvent(
                id: id,
                payload: payload,
                createdAtMs: _toInt(row['created_at']),
              );
            })
            .whereType<LearnedCandidateEvent>()
            .toList(growable: false);
      }
    }

    final pending = _memoryPendingEvents.values.toList(growable: false)
      ..sort((left, right) => left.createdAtMs.compareTo(right.createdAtMs));
    if (pending.length <= limit) {
      return pending;
    }
    return pending.take(limit).toList(growable: false);
  }

  Future<void> markCandidatesSubmitted(List<int> ids) async {
    if (ids.isEmpty || _disposed) {
      return;
    }
    await initialize();
    if (_dbAvailable) {
      final db = await _database.database;
      if (db != null) {
        final batch = db.batch();
        for (final id in ids) {
          batch.update(
            LearnedSignatureDb.candidateEventsTable,
            <String, Object?>{'status': 'submitted', 'last_error': null},
            where: 'id = ?',
            whereArgs: <Object?>[id],
          );
        }
        await batch.commit(noResult: true);
      }
    }
    for (final id in ids) {
      _memoryPendingEvents.remove(id);
    }
  }

  Future<void> markCandidateSubmitFailed(List<int> ids, {String? error}) async {
    if (ids.isEmpty || _disposed) {
      return;
    }
    await initialize();
    final nowMs = _now().millisecondsSinceEpoch;
    if (_dbAvailable) {
      final db = await _database.database;
      if (db != null) {
        final batch = db.batch();
        for (final id in ids) {
          batch.rawUpdate(
            '''
              UPDATE ${LearnedSignatureDb.candidateEventsTable}
              SET
                attempts = attempts + 1,
                status = 'pending',
                last_error = ?,
                next_retry_at = ?
              WHERE id = ?
            ''',
            <Object?>[error, nowMs + 120000, id],
          );
        }
        await batch.commit(noResult: true);
      }
    }
  }

  Future<void> applySnapshot({
    required int version,
    required String checksum,
    required List<LearnedSignature> signatures,
  }) async {
    if (_disposed) {
      return;
    }
    await initialize();
    final nowMs = _now().millisecondsSinceEpoch;
    final incomingHashes = <String>{};

    for (final incoming in signatures) {
      if (incoming.sigHash.isEmpty) {
        continue;
      }
      incomingHashes.add(incoming.sigHash);
      final existing = _signatures[incoming.sigHash];
      final merged = _mergeSignature(existing, incoming, nowMs: nowMs);
      _signatures[merged.sigHash] = merged;
      await _persistSignature(merged);
    }

    final staleCloud = _signatures.values
        .where(
          (entry) =>
              entry.source == LearnedSignatureSource.cloud &&
              !incomingHashes.contains(entry.sigHash),
        )
        .toList(growable: false);
    for (final stale in staleCloud) {
      final expired = stale.copyWith(
        state: LearnedSignatureState.expired,
        updatedAtMs: nowMs,
        lastReason: 'snapshot_removed',
      );
      _signatures[stale.sigHash] = expired;
      await _persistSignature(expired);
    }

    _snapshotVersion = version;
    _snapshotChecksum = checksum;
    await _writeSyncState('snapshot_version', '$version', nowMs: nowMs);
    await _writeSyncState('snapshot_checksum', checksum, nowMs: nowMs);
    await _writeSyncState('snapshot_updated_at', '$nowMs', nowMs: nowMs);
  }

  Future<void> _loadAll(Database db) async {
    final signatures = await db.query(
      LearnedSignatureDb.learnedSignaturesTable,
    );
    for (final row in signatures) {
      final signature = LearnedSignature.fromDbMap(row);
      if (signature.sigHash.isEmpty) {
        continue;
      }
      _signatures[signature.sigHash] = signature;
    }

    final syncRows = await db.query(LearnedSignatureDb.syncStateTable);
    for (final row in syncRows) {
      final key = (row['key'] ?? '').toString();
      final value = (row['value'] ?? '').toString();
      if (key == 'snapshot_version') {
        _snapshotVersion = int.tryParse(value) ?? 0;
      } else if (key == 'snapshot_checksum') {
        _snapshotChecksum = value;
      }
    }
  }

  Future<LearnedSignature> _upsertFromCandidate(
    CrowdSanitizedCandidate candidate, {
    required int nowMs,
    required String reason,
  }) async {
    final existing = _signatures[candidate.sigHash];
    if (existing == null) {
      final created = LearnedSignature(
        sigHash: candidate.sigHash,
        hostPattern: candidate.hostPattern,
        pathPattern: candidate.pathPattern,
        resourceType: candidate.resourceType,
        sourceHost: candidate.sourceHost,
        markerKeys: candidate.markerKeys,
        requireAdSignal: candidate.requireAdSignal,
        state: LearnedSignatureState.learning,
        source: LearnedSignatureSource.local,
        score: candidate.score,
        confidence: candidate.confidence,
        seenCount: 1,
        falsePositiveCount: 0,
        firstSeenAtMs: nowMs,
        lastSeenAtMs: nowMs,
        expireAtMs: nowMs + const Duration(days: 45).inMilliseconds,
        updatedAtMs: nowMs,
        lastReason: reason,
      );
      final next = _maybePromote(created);
      _signatures[next.sigHash] = next;
      await _persistSignature(next);
      return next;
    }

    final nextSeenCount = existing.seenCount + 1;
    final nextScore = ((existing.score * 0.72) + (candidate.score * 0.28) + 2)
        .clamp(0, 100)
        .toDouble();
    final nextConfidence =
        ((existing.confidence * 0.74) + (candidate.confidence * 0.26))
            .clamp(0, 1)
            .toDouble();

    final updated = existing.copyWith(
      hostPattern: existing.source == LearnedSignatureSource.cloud
          ? existing.hostPattern
          : candidate.hostPattern,
      pathPattern: existing.source == LearnedSignatureSource.cloud
          ? existing.pathPattern
          : candidate.pathPattern,
      sourceHost: existing.source == LearnedSignatureSource.cloud
          ? existing.sourceHost
          : candidate.sourceHost,
      markerKeys: _mergeMarkerKeys(existing.markerKeys, candidate.markerKeys),
      requireAdSignal: existing.requireAdSignal && candidate.requireAdSignal,
      seenCount: nextSeenCount,
      score: nextScore,
      confidence: nextConfidence,
      lastSeenAtMs: nowMs,
      updatedAtMs: nowMs,
      lastReason: reason,
      expireAtMs: nowMs + const Duration(days: 45).inMilliseconds,
    );

    final promoted = _maybePromote(updated);
    _signatures[promoted.sigHash] = promoted;
    await _persistSignature(promoted);
    return promoted;
  }

  Future<void> _setLastReason(
    String sigHash, {
    required String reason,
    required int nowMs,
  }) async {
    final existing = _signatures[sigHash];
    if (existing == null) {
      return;
    }
    final updated = existing.copyWith(lastReason: reason, updatedAtMs: nowMs);
    _signatures[sigHash] = updated;
    await _persistSignature(updated);
  }

  LearnedSignature _maybePromote(LearnedSignature signature) {
    if (signature.state != LearnedSignatureState.learning) {
      return signature;
    }
    if (signature.falsePositiveCount >= 2) {
      return signature;
    }
    if (signature.seenCount < 3) {
      return signature;
    }
    if (signature.score < 82 || signature.confidence < 0.86) {
      return signature;
    }
    return signature.copyWith(state: LearnedSignatureState.active);
  }

  List<String> _mergeMarkerKeys(List<String> left, List<String> right) {
    final merged = <String>{...left, ...right}.toList(growable: false)..sort();
    if (merged.length > 24) {
      return merged.take(24).toList(growable: false);
    }
    return merged;
  }

  LearnedSignature _mergeSignature(
    LearnedSignature? existing,
    LearnedSignature incoming, {
    required int nowMs,
  }) {
    if (existing == null) {
      return incoming.copyWith(
        source: LearnedSignatureSource.cloud,
        updatedAtMs: nowMs,
      );
    }
    if (existing.state == LearnedSignatureState.quarantined &&
        existing.falsePositiveCount >= 3) {
      return existing.copyWith(updatedAtMs: nowMs);
    }
    return incoming.copyWith(
      source: LearnedSignatureSource.cloud,
      seenCount: existing.seenCount > incoming.seenCount
          ? existing.seenCount
          : incoming.seenCount,
      falsePositiveCount: existing.falsePositiveCount,
      score: incoming.score > existing.score ? incoming.score : existing.score,
      confidence: incoming.confidence > existing.confidence
          ? incoming.confidence
          : existing.confidence,
      firstSeenAtMs: existing.firstSeenAtMs,
      lastSeenAtMs: nowMs,
      updatedAtMs: nowMs,
      lastReason: incoming.lastReason ?? existing.lastReason,
    );
  }

  Future<void> _enqueueCandidate(
    CrowdSanitizedCandidate candidate, {
    required int nowMs,
  }) async {
    if (_dbAvailable) {
      final db = await _database.database;
      if (db != null) {
        await db
            .insert(LearnedSignatureDb.candidateEventsTable, <String, Object?>{
              'sig_hash': candidate.sigHash,
              'payload': jsonEncode(candidate.toMap()),
              'created_at': nowMs,
              'status': 'pending',
              'attempts': 0,
              'next_retry_at': null,
              'last_error': null,
            });
        return;
      }
      _dbAvailable = false;
    }

    final id = _nextMemoryCandidateId;
    _nextMemoryCandidateId -= 1;
    _memoryPendingEvents[id] = LearnedCandidateEvent(
      id: id,
      payload: candidate,
      createdAtMs: nowMs,
    );
  }

  Future<void> _persistSignature(LearnedSignature signature) async {
    if (_dbAvailable) {
      final db = await _database.database;
      if (db != null) {
        await db.insert(
          LearnedSignatureDb.learnedSignaturesTable,
          signature.toDbMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        return;
      }
      _dbAvailable = false;
    }
  }

  Future<void> _writeSyncState(
    String key,
    String value, {
    required int nowMs,
  }) async {
    if (!_dbAvailable) {
      return;
    }
    final db = await _database.database;
    if (db == null) {
      _dbAvailable = false;
      return;
    }
    await db.insert(
      LearnedSignatureDb.syncStateTable,
      <String, Object?>{'key': key, 'value': value, 'updated_at': nowMs},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  int _toInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim()) ?? 0;
    }
    return 0;
  }

  void _logSuspiciousLink({
    required CrowdSanitizedCandidate candidate,
    required LearnedSignature signature,
    required String reason,
    required String action,
  }) {
    _log(
      '$action total=$_suspiciousLinkTotal sig=${_shortSig(signature.sigHash)} status=${signature.state}/${_statusLevel(signature)} seen=${signature.seenCount} fp=${signature.falsePositiveCount} score=${signature.score.toStringAsFixed(1)} conf=${signature.confidence.toStringAsFixed(2)} reason=$reason host=${candidate.hostPattern} path=${candidate.pathPattern} markers=${candidate.markerKeys.length}',
    );
  }

  String _statusLevel(LearnedSignature signature) {
    if (signature.state == LearnedSignatureState.quarantined) {
      return 'critical';
    }
    if (signature.state == LearnedSignatureState.expired) {
      return 'inactive';
    }
    if (signature.state == LearnedSignatureState.active) {
      if (signature.confidence >= 0.94 && signature.score >= 90) {
        return 'high';
      }
      return 'medium';
    }
    if (signature.seenCount >= 3 && signature.confidence >= 0.86) {
      return 'learning_high';
    }
    if (signature.seenCount >= 2) {
      return 'learning_medium';
    }
    return 'learning_low';
  }

  String _shortSig(String sigHash) {
    if (sigHash.length <= 12) {
      return sigHash;
    }
    return sigHash.substring(0, 12);
  }

  void _log(String message) {
    if (!_debugLoggingEnabled || _crowdLearnLogCount >= _maxCrowdLearnLogs) {
      return;
    }
    _crowdLearnLogCount += 1;
    final line = '[GO_PLAY-CrowdLearn] $message';
    final sink = _logSink;
    if (sink != null) {
      sink(line);
      return;
    }
    // ignore: avoid_print
    print(line);
  }
}
