import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../app/config/auth_config.dart';
import '../domain/models/subscription_record.dart';

class SubscriptionService {
  SubscriptionService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection(AuthConfig.usersCollectionPath);

  Future<SubscriptionRecord> ensureSubscription({required User user}) async {
    final current = await getCurrentSubscription(user: user);
    if (current != null) {
      return current;
    }
    try {
      await _bootstrapUserDocument(user: user);
    } catch (_) {
      // Fall through to read/fallback response so login can continue.
    }
    final afterBootstrap = await getCurrentSubscription(user: user);
    if (afterBootstrap != null) {
      return afterBootstrap;
    }
    final now = DateTime.now().toUtc();
    return SubscriptionRecord(
      id: user.uid,
      email: (user.email ?? '').trim(),
      emailLower: (user.email ?? '').trim().toLowerCase(),
      uid: user.uid,
      expiryDate: now,
      expiryDateText: _formatYyyyMmDd(now),
      status: 'expired',
      plan: 'default',
      startAt: now,
      maxDevices: AuthConfig.defaultMaxDevices,
      extraDays: 0,
      version: 1,
      createdAt: now,
      updatedAt: now,
      updatedBy: 'client_bootstrap_fallback',
      source: 'users/${user.uid}',
    );
  }

  Future<SubscriptionRecord?> getCurrentSubscription({
    required User user,
  }) async {
    final doc = await _users.doc(user.uid).get();
    if (!doc.exists) {
      return null;
    }
    final data = doc.data();
    if (data == null) {
      return null;
    }
    return _subscriptionFromUserDoc(doc.id, user, data);
  }

  Future<DateTime?> getExpiryDate({required User user}) async {
    final subscription = await getCurrentSubscription(user: user);
    return subscription?.expiryDate;
  }

  Future<bool> isSubscriptionActive({required User user}) async {
    final subscription = await getCurrentSubscription(user: user);
    if (subscription == null) {
      return false;
    }
    return isRecordActive(subscription);
  }

  bool isRecordActive(SubscriptionRecord subscription) {
    return subscription.isActive;
  }

  SubscriptionRecord _subscriptionFromUserDoc(
    String uid,
    User user,
    Map<String, dynamic> data,
  ) {
    final subscription = _asMap(data['subscription']);
    final createdAt = _toDateTime(data['createdAt']) ?? DateTime.now().toUtc();
    final startAt = _toDateTime(subscription['startAt']) ?? createdAt;
    final expireAt = _toDateTime(subscription['expireAt']) ?? createdAt;
    final status = _normalizeStatus(
      (subscription['status'] ?? 'active').toString(),
      expireAt,
    );
    final email = _normalizedEmailFromDoc(data['email'], user.email);
    return SubscriptionRecord(
      id: uid,
      email: email,
      emailLower: email.toLowerCase(),
      uid: uid,
      expiryDate: expireAt,
      expiryDateText: _formatYyyyMmDd(expireAt),
      status: status,
      plan: (subscription['plan'] ?? '').toString().trim(),
      startAt: startAt,
      maxDevices: _toInt(subscription['maxDevices']),
      extraDays: _toInt(subscription['extraDays']),
      version: _toInt(subscription['version']),
      createdAt: createdAt,
      updatedAt: _toDateTime(subscription['updatedAt'] ?? data['updatedAt']),
      updatedBy: (subscription['updatedBy'] ?? '').toString().trim(),
      source: 'users/$uid',
    );
  }

  Future<void> _bootstrapUserDocument({required User user}) async {
    final docRef = _users.doc(user.uid);
    final now = DateTime.now().toUtc();
    await docRef.set(<String, dynamic>{
      'email': (user.email ?? '').trim(),
      'displayName': (user.displayName ?? '').trim(),
      'photoURL': (user.photoURL ?? '').trim(),
      'subscription': <String, dynamic>{
        'plan': 'default',
        'status': 'active',
        'startAt': Timestamp.fromDate(now),
        'expireAt': Timestamp.fromDate(now),
        'maxDevices': AuthConfig.defaultMaxDevices,
        'extraDays': 0,
        'version': 1,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': 'client_bootstrap',
      },
      'stats': <String, dynamic>{
        'activeDeviceCount': 0,
      },
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, dynamic v) => MapEntry(key.toString(), v));
    }
    return const <String, dynamic>{};
  }

  DateTime? _toDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate().toUtc();
    }
    if (value is DateTime) {
      return value.toUtc();
    }
    if (value is String) {
      return DateTime.tryParse(value)?.toUtc();
    }
    return null;
  }

  int? _toInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  String _normalizeStatus(String status, DateTime expireAt) {
    final normalized = status.trim().toLowerCase();
    if (normalized == 'blocked') {
      return 'blocked';
    }
    if (!expireAt.toUtc().isAfter(DateTime.now().toUtc())) {
      return 'expired';
    }
    if (normalized == 'expired') {
      return 'expired';
    }
    return 'active';
  }

  String _normalizedEmailFromDoc(dynamic docEmail, String? authEmail) {
    final fromDoc = (docEmail ?? '').toString().trim();
    if (fromDoc.isNotEmpty) {
      return fromDoc;
    }
    return (authEmail ?? '').trim();
  }

  String _formatYyyyMmDd(DateTime dateTime) {
    final local = dateTime.toLocal();
    final yyyy = local.year.toString().padLeft(4, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd';
  }
}
