import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../app/config/auth_config.dart';
import '../domain/auth_exceptions.dart';
import '../domain/models/auth_session.dart';

class AuthSessionService {
  AuthSessionService({
    FirebaseFirestore? firestore,
    int maxSessionsPerEmail = AuthConfig.maxSessionsPerEmail,
    Duration sessionTtl = AuthConfig.sessionTtl,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _maxSessionsPerEmail = maxSessionsPerEmail,
       _sessionTtl = sessionTtl;

  final FirebaseFirestore _firestore;
  final int _maxSessionsPerEmail;
  final Duration _sessionTtl;

  CollectionReference<Map<String, dynamic>> get _sessions =>
      _firestore.collection(AuthConfig.sessionsCollectionPath);

  Future<AuthSession> ensureActiveSession({
    required User user,
    String? existingSessionId,
  }) async {
    final normalizedEmail = _normalizedEmail(user);
    _log(
      'ensureActiveSession uid=${user.uid} email=${user.email ?? "-"} hasExistingSession=${(existingSessionId ?? "").trim().isNotEmpty}',
    );
    if (normalizedEmail == null) {
      throw FirebaseAuthException(
        code: 'missing-email',
        message: 'Google account does not contain a usable email.',
      );
    }

    if (existingSessionId != null && existingSessionId.trim().isNotEmpty) {
      final existing = await _validateExistingSession(
        sessionId: existingSessionId.trim(),
        user: user,
        normalizedEmail: normalizedEmail,
      );
      if (existing != null) {
        _log('ensureActiveSession reuse existing session=${existing.id}');
        return existing;
      }
      _log('ensureActiveSession existing session not found in Firestore');
    }

    _log('ensureActiveSession creating new session');
    return _createSession(user: user, normalizedEmail: normalizedEmail);
  }

  Future<void> revokeSession(String sessionId) async {
    final normalizedSessionId = sessionId.trim();
    if (normalizedSessionId.isEmpty) {
      return;
    }
    _log('revokeSession session=$normalizedSessionId');
    await _sessions.doc(normalizedSessionId).set(<String, dynamic>{
      'status': 'revoked',
      'revokedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<AuthSession?> _validateExistingSession({
    required String sessionId,
    required User user,
    required String normalizedEmail,
  }) async {
    final doc = await _sessions.doc(sessionId).get();
    if (!doc.exists) {
      _log('_validateExistingSession not found session=$sessionId');
      return null;
    }
    final data = doc.data();
    if (data == null) {
      return null;
    }

    final uid = (data['uid'] ?? '').toString().trim();
    final email = (data['email'] ?? '').toString().trim().toLowerCase();
    final status = (data['status'] ?? '').toString().trim().toLowerCase();
    final expiresAt = _toDateTime(data['expiresAt']);

    if (uid != user.uid || email != normalizedEmail || status != 'active') {
      _log(
        '_validateExistingSession invalid session=$sessionId uid=$uid email=$email status=$status expectedUid=${user.uid} expectedEmail=$normalizedEmail',
      );
      throw SessionInvalidException();
    }
    if (expiresAt == null || !expiresAt.isAfter(DateTime.now().toUtc())) {
      _log('_validateExistingSession expired session=$sessionId');
      await _sessions.doc(sessionId).set(<String, dynamic>{
        'status': 'expired',
        'revokedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      throw SessionExpiredException();
    }

    await _sessions.doc(sessionId).set(<String, dynamic>{
      'lastSeenAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    _log('_validateExistingSession success session=$sessionId');
    return _sessionFromDoc(doc.id, data);
  }

  Future<AuthSession> _createSession({
    required User user,
    required String normalizedEmail,
  }) async {
    final activeCount = await _activeSessionCountForEmail(
      normalizedEmail: normalizedEmail,
      uid: user.uid,
    );
    _log(
      '_createSession email=$normalizedEmail uid=${user.uid} activeCount=$activeCount max=$_maxSessionsPerEmail',
    );
    if (activeCount >= _maxSessionsPerEmail) {
      throw SessionLimitExceededException(limit: _maxSessionsPerEmail);
    }

    final expiresAt = DateTime.now().toUtc().add(_sessionTtl);
    final docRef = _sessions.doc();
    await docRef.set(<String, dynamic>{
      'sessionId': docRef.id,
      'uid': user.uid,
      'email': normalizedEmail,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'revokedAt': null,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'platform': _platformLabel(),
      // TODO(security-backend): Move final trust/premium authorization to
      // server-side verification using signed trust context from
      // ServerTrustService + backend nonce validation.
      'trustState': 'server_validation_required',
    });
    final created = await docRef.get();
    final createdData = created.data();
    if (createdData == null) {
      throw StateError('Created session has no data.');
    }
    _log('_createSession success session=${created.id}');
    return _sessionFromDoc(created.id, createdData);
  }

  Future<int> _activeSessionCountForEmail({
    required String normalizedEmail,
    required String uid,
  }) async {
    final now = Timestamp.fromDate(DateTime.now().toUtc());
    final snapshot = await _sessions
        .where('email', isEqualTo: normalizedEmail)
        .where('uid', isEqualTo: uid)
        .where('status', isEqualTo: 'active')
        .where('expiresAt', isGreaterThan: now)
        .get();
    return snapshot.size;
  }

  String? _normalizedEmail(User user) {
    final email = (user.email ?? '').trim().toLowerCase();
    if (email.isEmpty) {
      return null;
    }
    return email;
  }

  String _platformLabel() {
    if (kIsWeb) {
      return 'web';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  DateTime? _toDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate().toUtc();
    }
    if (value is DateTime) {
      return value.toUtc();
    }
    return null;
  }

  AuthSession _sessionFromDoc(String id, Map<String, dynamic> data) {
    final expiresAt = _toDateTime(data['expiresAt']);
    if (expiresAt == null) {
      throw StateError('Session document missing expiresAt.');
    }
    return AuthSession(
      id: id,
      uid: (data['uid'] ?? '').toString().trim(),
      email: (data['email'] ?? '').toString().trim(),
      createdAt: _toDateTime(data['createdAt']),
      lastSeenAt: _toDateTime(data['lastSeenAt']),
      expiresAt: expiresAt,
      status: (data['status'] ?? '').toString().trim(),
    );
  }

  void _log(String message) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('[GO_PLAY-AuthSession] $message');
  }
}
