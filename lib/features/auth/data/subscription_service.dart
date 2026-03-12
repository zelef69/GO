import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../app/config/auth_config.dart';
import '../domain/models/subscription_record.dart';

class SubscriptionService {
  SubscriptionService({
    FirebaseFirestore? firestore,
    Duration initialSubscriptionDuration =
        AuthConfig.initialSubscriptionDuration,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _initialSubscriptionDuration = initialSubscriptionDuration;

  final FirebaseFirestore _firestore;
  final Duration _initialSubscriptionDuration;

  CollectionReference<Map<String, dynamic>> get _subscriptions =>
      _firestore.collection(AuthConfig.subscriptionsCollectionPath);

  Future<SubscriptionRecord> ensureSubscription({required User user}) async {
    final normalizedEmail = _normalizedEmail(user);
    if (normalizedEmail == null) {
      throw FirebaseAuthException(
        code: 'missing-email',
        message: 'Google account does not contain a usable email.',
      );
    }

    final docRef = _subscriptions.doc(normalizedEmail);
    try {
      final current = await docRef.get();
      if (current.exists) {
        final data = current.data();
        if (data == null) {
          throw StateError('Subscription exists but has no data.');
        }
        final syncPatch = _buildExistingSyncPatch(
          user: user,
          normalizedEmail: normalizedEmail,
          data: data,
        );
        if (syncPatch.isNotEmpty) {
          await docRef.set(syncPatch, SetOptions(merge: true));
          _log(
            'subscription synced email=$normalizedEmail fields=${syncPatch.keys.join(",")}',
          );
        }

        final latest = await docRef.get();
        final latestData = latest.data() ?? data;
        final subscription = _subscriptionFromDoc(latest.id, latestData);
        _log(
          'subscription found email=$normalizedEmail uid=${subscription.uid} expiry=${subscription.expiryDate.toIso8601String()} status=${subscription.status}',
        );
        return subscription;
      }

      return _createInitialSubscription(
        docRef: docRef,
        user: user,
        normalizedEmail: normalizedEmail,
      );
    } on FirebaseException catch (error) {
      _log(
        'ensureSubscription firebase_error code=${error.code} message=${error.message ?? "-"} path=subscriptions/$normalizedEmail',
      );
      rethrow;
    }
  }

  Future<SubscriptionRecord> _createInitialSubscription({
    required DocumentReference<Map<String, dynamic>> docRef,
    required User user,
    required String normalizedEmail,
  }) async {
    final initialExpiry = _buildInitialExpiryDateUtc();
    final email = (user.email ?? normalizedEmail).trim();
    await docRef.set(<String, dynamic>{
      'email': email,
      'emailLower': normalizedEmail,
      'uid': user.uid,
      'expiryDate': Timestamp.fromDate(initialExpiry),
      'expiryDateText': _formatYyyyMmDd(initialExpiry),
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': 'login_init',
      'source': 'login_init',
    }, SetOptions(merge: true));

    final created = await docRef.get();
    final createdData = created.data();
    if (createdData == null) {
      throw StateError('Created subscription has no data.');
    }
    final createdSubscription = _subscriptionFromDoc(created.id, createdData);
    _log(
      'subscription created email=$normalizedEmail uid=${user.uid} expiry=${createdSubscription.expiryDate.toIso8601String()}',
    );
    return createdSubscription;
  }

  Map<String, dynamic> _buildExistingSyncPatch({
    required User user,
    required String normalizedEmail,
    required Map<String, dynamic> data,
  }) {
    final patch = <String, dynamic>{};
    final currentUid = (data['uid'] ?? '').toString().trim();
    if (currentUid.isEmpty || currentUid != user.uid) {
      patch['uid'] = user.uid;
    }

    final authEmail = (user.email ?? normalizedEmail).trim();
    final currentEmail = (data['email'] ?? '').toString().trim();
    if (currentEmail.isEmpty) {
      patch['email'] = authEmail;
    }

    final currentEmailLower = (data['emailLower'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (currentEmailLower.isEmpty || currentEmailLower != normalizedEmail) {
      patch['emailLower'] = normalizedEmail;
    }

    final expiryDate = _toDateTime(data['expiryDate']);
    final expiryDateText = (data['expiryDateText'] ?? '').toString().trim();
    if (expiryDate != null && expiryDateText.isEmpty) {
      patch['expiryDateText'] = _formatYyyyMmDd(expiryDate);
    }

    final status = (data['status'] ?? '').toString().trim();
    if (status.isEmpty) {
      patch['status'] = 'active';
    }

    if (patch.isNotEmpty) {
      patch['updatedAt'] = FieldValue.serverTimestamp();
      patch['updatedBy'] = 'login_sync';
      patch['source'] = 'login_sync';
    }
    return patch;
  }

  Future<SubscriptionRecord?> getCurrentSubscription({
    required User user,
  }) async {
    final normalizedEmail = _normalizedEmail(user);
    if (normalizedEmail == null) {
      return null;
    }
    final doc = await _subscriptions.doc(normalizedEmail).get();
    if (!doc.exists) {
      return null;
    }
    final data = doc.data();
    if (data == null) {
      return null;
    }
    return _subscriptionFromDoc(doc.id, data);
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

  DateTime _buildInitialExpiryDateUtc() {
    return DateTime.now().toUtc().add(_initialSubscriptionDuration);
  }

  String _formatYyyyMmDd(DateTime dateTime) {
    final local = dateTime.toLocal();
    final yyyy = local.year.toString().padLeft(4, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd';
  }

  String? _normalizedEmail(User user) {
    final email = (user.email ?? '').trim().toLowerCase();
    if (email.isEmpty) {
      return null;
    }
    return email;
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

  SubscriptionRecord _subscriptionFromDoc(
    String id,
    Map<String, dynamic> data,
  ) {
    final expiryDate = _toDateTime(data['expiryDate']);
    if (expiryDate == null) {
      throw StateError('Subscription document missing expiryDate.');
    }

    final rawStatus = (data['status'] ?? '').toString().trim();
    final normalizedStatus = rawStatus.isEmpty ? 'active' : rawStatus;
    return SubscriptionRecord(
      id: id,
      email: (data['email'] ?? '').toString().trim(),
      emailLower: (data['emailLower'] ?? '').toString().trim().toLowerCase(),
      uid: (data['uid'] ?? '').toString().trim(),
      expiryDate: expiryDate,
      expiryDateText: (data['expiryDateText'] ?? '').toString().trim(),
      status: normalizedStatus,
      createdAt: _toDateTime(data['createdAt']),
      updatedAt: _toDateTime(data['updatedAt']),
      updatedBy: (data['updatedBy'] ?? '').toString().trim(),
      source: (data['source'] ?? '').toString().trim(),
    );
  }

  void _log(String message) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('[GO_PLAY-Subscription] $message');
  }
}
