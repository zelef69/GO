import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../storage/learned_signature_repository.dart';
import 'crowd_manifest.dart';

class CrowdSyncService {
  CrowdSyncService({
    required FirebaseFunctions functions,
    required LearnedSignatureRepository repository,
    required bool debugMode,
    Dio? dio,
    DateTime Function()? now,
  }) : _functions = functions,
       _repository = repository,
       _debugMode = debugMode,
       _dio = dio ?? Dio(),
       _now = now ?? DateTime.now;

  final FirebaseFunctions _functions;
  final LearnedSignatureRepository _repository;
  final bool _debugMode;
  final Dio _dio;
  final DateTime Function() _now;

  static const String _submitCandidateFn = 'submitAdCandidate';
  static const String _fetchManifestFn = 'fetchSignatureManifest';
  static const Duration _callTimeout = Duration(seconds: 18);
  static const Duration _debounceDelay = Duration(seconds: 2);
  static const Duration _minimumSyncInterval = Duration(minutes: 2);
  static const int _maxSubmitBatch = 25;

  bool _initialized = false;
  bool _syncInFlight = false;
  bool _functionsUnavailable = false;
  bool _crowdLearningEnabled = true;
  bool _crowdSyncEnabled = true;
  DateTime? _lastSyncAt;
  Timer? _syncDebounceTimer;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    await _repository.initialize();
    _initialized = true;
  }

  void updateFlags({
    required bool crowdLearningEnabled,
    required bool crowdSyncEnabled,
  }) {
    _crowdLearningEnabled = crowdLearningEnabled;
    _crowdSyncEnabled = crowdSyncEnabled;
  }

  void scheduleSync({required String reason}) {
    if (!_crowdLearningEnabled || !_crowdSyncEnabled) {
      return;
    }
    _syncDebounceTimer?.cancel();
    _syncDebounceTimer = Timer(_debounceDelay, () {
      unawaited(syncNow(reason: 'scheduled:$reason'));
    });
  }

  Future<void> syncNow({required String reason, bool force = false}) async {
    if (!_crowdLearningEnabled || !_crowdSyncEnabled) {
      return;
    }
    if (!_initialized) {
      await initialize();
    }
    if (_syncInFlight) {
      return;
    }
    final now = _now();
    if (!force &&
        _lastSyncAt != null &&
        now.difference(_lastSyncAt!) < _minimumSyncInterval) {
      return;
    }

    _syncInFlight = true;
    try {
      await _submitPendingCandidates();
      await _fetchAndApplySnapshot();
      _lastSyncAt = now;
      _log('sync completed reason=$reason');
    } catch (error) {
      _log('sync failed reason=$reason error=$error');
    } finally {
      _syncInFlight = false;
    }
  }

  Future<void> dispose() async {
    _syncDebounceTimer?.cancel();
    _syncDebounceTimer = null;
  }

  Future<void> _submitPendingCandidates() async {
    if (_functionsUnavailable) {
      return;
    }
    final events = await _repository.takePendingCandidates(
      limit: _maxSubmitBatch,
    );
    if (events.isEmpty) {
      return;
    }

    final callable = _functions.httpsCallable(_submitCandidateFn);
    final payload = <String, dynamic>{
      'candidates': events
          .map((event) {
            final map = event.payload.toMap();
            map['clientEventId'] = event.id;
            return map;
          })
          .toList(growable: false),
      'clientTimeMs': _now().millisecondsSinceEpoch,
    };

    try {
      final response = await callable.call(payload).timeout(_callTimeout);
      final data = _asMap(response.data);
      final accepted = _asIntList(data['acceptedIds']);
      final rejected = _asIntList(data['rejectedIds']);
      if (accepted.isNotEmpty || rejected.isNotEmpty) {
        if (accepted.isNotEmpty) {
          await _repository.markCandidatesSubmitted(accepted);
        }
        if (rejected.isNotEmpty) {
          await _repository.markCandidatesSubmitted(rejected);
        }
      } else {
        await _repository.markCandidatesSubmitted(
          events.map((event) => event.id).toList(growable: false),
        );
      }
    } on FirebaseFunctionsException catch (error) {
      if (_isFunctionUnavailable(error)) {
        _functionsUnavailable = true;
        _log('submit pending disabled functions code=${error.code}');
        return;
      }
      await _repository.markCandidateSubmitFailed(
        events.map((event) => event.id).toList(growable: false),
        error: error.message,
      );
    } catch (error) {
      await _repository.markCandidateSubmitFailed(
        events.map((event) => event.id).toList(growable: false),
        error: error.toString(),
      );
    }
  }

  Future<void> _fetchAndApplySnapshot() async {
    if (_functionsUnavailable) {
      return;
    }
    final callable = _functions.httpsCallable(_fetchManifestFn);
    final payload = <String, dynamic>{
      'currentVersion': _repository.snapshotVersion,
    };

    late CrowdSignatureManifest manifest;
    try {
      final response = await callable.call(payload).timeout(_callTimeout);
      manifest = CrowdSignatureManifest.fromMap(_asMap(response.data));
    } on FirebaseFunctionsException catch (error) {
      if (_isFunctionUnavailable(error)) {
        _functionsUnavailable = true;
        _log('fetch manifest disabled functions code=${error.code}');
      }
      return;
    } catch (_) {
      return;
    }

    if (manifest.upToDate || !manifest.hasDownload || manifest.version <= 0) {
      return;
    }

    final response = await _dio.get<List<int>>(
      manifest.downloadUrl,
      options: Options(responseType: ResponseType.bytes, followRedirects: true),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      return;
    }

    List<int> snapshotBytes = bytes;
    final isGzip = manifest.storagePath.toLowerCase().endsWith('.gz');
    if (isGzip) {
      try {
        snapshotBytes = gzip.decode(bytes);
      } catch (_) {
        return;
      }
    }

    final checksum = sha256.convert(snapshotBytes).toString();
    if (manifest.checksum.isNotEmpty &&
        checksum.toLowerCase() != manifest.checksum.toLowerCase()) {
      _log(
        'snapshot checksum mismatch expected=${manifest.checksum} actual=$checksum',
      );
      return;
    }

    final snapshotRaw = utf8.decode(snapshotBytes);
    final decoded = jsonDecode(snapshotRaw);
    if (decoded is! Map<String, dynamic>) {
      return;
    }

    final snapshot = CrowdSignatureSnapshot.fromMap(decoded);
    if (snapshot.version <= 0) {
      return;
    }
    await _repository.applySnapshot(
      version: snapshot.version,
      checksum: snapshot.checksum.isNotEmpty ? snapshot.checksum : checksum,
      signatures: snapshot.signatures,
    );
  }

  bool _isFunctionUnavailable(FirebaseFunctionsException error) {
    final code = error.code.toLowerCase();
    if (code == 'not-found' || code == 'unimplemented') {
      return true;
    }
    final message = (error.message ?? '').toLowerCase();
    return message.contains('not found') || message.contains('not_found');
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
    }
    return const <String, dynamic>{};
  }

  List<int> _asIntList(dynamic value) {
    if (value is! List) {
      return const <int>[];
    }
    final output = <int>[];
    for (final entry in value) {
      if (entry is num) {
        output.add(entry.toInt());
      } else if (entry is String) {
        final parsed = int.tryParse(entry.trim());
        if (parsed != null) {
          output.add(parsed);
        }
      }
    }
    return output;
  }

  void _log(String message) {
    if (!_debugMode) {
      return;
    }
    // ignore: avoid_print
    print('[GO_PLAY-CrowdSync] $message');
  }
}
