import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../session/session_service.dart';
import '../../services/security_service.dart';
import 'data/auth_session_service.dart';
import 'data/firebase_auth_service.dart';
import 'data/local_session_store.dart';
import 'data/subscription_service.dart';
import 'domain/auth_exceptions.dart';
import 'domain/models/subscription_record.dart';

enum AuthStatus {
  initializing,
  checkingSession,
  unauthenticated,
  authenticating,
  authenticated,
  blocked,
  error,
}

class AuthController extends ChangeNotifier {
  AuthController({
    required FirebaseAuthService firebaseAuthService,
    required SubscriptionService subscriptionService,
    required AuthSessionService authSessionService,
    required LocalSessionStore localSessionStore,
    required SessionService browserSessionService,
  }) : _firebaseAuthService = firebaseAuthService,
       _subscriptionService = subscriptionService,
       _authSessionService = authSessionService,
       _localSessionStore = localSessionStore,
       _browserSessionService = browserSessionService;

  final FirebaseAuthService _firebaseAuthService;
  final SubscriptionService _subscriptionService;
  final AuthSessionService _authSessionService;
  final LocalSessionStore _localSessionStore;
  final SessionService _browserSessionService;
  static const Duration _signInTimeout = Duration(seconds: 45);

  StreamSubscription<User?>? _authStateSubscription;
  bool _initialized = false;
  int _refreshToken = 0;
  String? _activeAuthSessionId;

  AuthStatus _status = AuthStatus.initializing;
  User? _currentUser;
  SubscriptionRecord? _currentSubscription;
  String? _message;

  AuthStatus get status => _status;
  User? get currentUser => _currentUser;
  SubscriptionRecord? get currentSubscription => _currentSubscription;
  // Backward-compatible alias for existing UI code paths.
  SubscriptionRecord? get currentSession => _currentSubscription;
  String? get message => _message;

  bool get isAuthenticated =>
      _status == AuthStatus.authenticated &&
      _currentUser != null &&
      _currentSubscription != null;

  Future<void> initialize() async {
    if (_initialized) {
      _log('initialize skipped (already initialized)');
      return;
    }
    _log('initialize start');
    _initialized = true;
    _authStateSubscription = _firebaseAuthService.authStateChanges().listen((
      user,
    ) {
      _log(
        'authStateChanges event user=${user?.uid ?? "null"} email=${user?.email ?? "-"}',
      );
      unawaited(_syncFromAuthState(reason: 'auth_state_changed'));
    });
    await _syncFromAuthState(reason: 'initialize');
  }

  Future<void> signInWithGoogle() async {
    if (_status == AuthStatus.authenticating) {
      _log('signInWithGoogle ignored (already authenticating)');
      return;
    }
    await SecurityService.instance.checkpointSensitiveAction('auth_sign_in');
    _log('signInWithGoogle start');
    _setState(status: AuthStatus.authenticating, message: null);
    try {
      final credential = await _firebaseAuthService.signInWithGoogle().timeout(
        _signInTimeout,
      );
      if (credential == null) {
        _log('signInWithGoogle canceled/interrupted');
        _setState(
          status: AuthStatus.unauthenticated,
          message: 'Sign-in was canceled or interrupted. Please try again.',
        );
        return;
      }
      _log(
        'signInWithGoogle credential acquired uid=${credential.user?.uid ?? "null"}',
      );
      await _syncFromAuthState(reason: 'google_sign_in');
    } on TimeoutException {
      _log('signInWithGoogle timeout after ${_signInTimeout.inSeconds}s');
      _setState(
        status: AuthStatus.error,
        message: 'Google sign-in timed out. Please check your network.',
      );
    } on FirebaseAuthException catch (error) {
      _log(
        'signInWithGoogle FirebaseAuthException code=${error.code} message=${error.message}',
      );
      _setState(
        status: AuthStatus.error,
        message: error.message ?? 'Google sign-in failed.',
      );
    } catch (error) {
      _log('signInWithGoogle exception=$error');
      _setState(
        status: AuthStatus.error,
        message: 'Google sign-in failed: $error',
      );
    }
  }

  Future<void> signOut() async {
    await SecurityService.instance.checkpointSensitiveAction('auth_sign_out');
    _log('signOut start');
    final signedInUser = _firebaseAuthService.currentUser;
    await _browserSessionService.clearSessionAndCache();
    await _releaseAuthSession(user: signedInUser);
    await _firebaseAuthService.signOut();
    _log('signOut complete');
    _setState(
      status: AuthStatus.unauthenticated,
      user: null,
      subscription: null,
      message: null,
    );
  }

  Future<void> _syncFromAuthState({required String reason}) async {
    final token = ++_refreshToken;
    final user = _firebaseAuthService.currentUser;
    _log(
      '_syncFromAuthState reason=$reason token=$token user=${user?.uid ?? "null"}',
    );
    if (user == null) {
      _activeAuthSessionId = null;
      _setState(
        status: AuthStatus.unauthenticated,
        user: null,
        subscription: null,
        message: null,
      );
      return;
    }

    _setState(status: AuthStatus.checkingSession, user: user, message: null);
    if (token != _refreshToken) {
      _log('_syncFromAuthState aborted (stale token) token=$token');
      return;
    }

    try {
      final subscription = await _subscriptionService.ensureSubscription(
        user: user,
      );
      if (token != _refreshToken) {
        _log(
          '_syncFromAuthState aborted after ensureSubscription (stale token)',
        );
        return;
      }

      final subscriptionActive = _subscriptionService.isRecordActive(
        subscription,
      );
      if (!subscriptionActive) {
        final expiredOn = subscription.expiryDateText.isNotEmpty
            ? subscription.expiryDateText
            : _formatYyyyMmDd(subscription.expiryDate);
        _log(
          '_syncFromAuthState blocked expired uid=${user.uid} email=${subscription.emailLower} expiredOn=$expiredOn',
        );
        await _browserSessionService.clearSessionAndCache();
        await _releaseAuthSession(user: user);
        await _firebaseAuthService.signOut();
        if (token != _refreshToken) {
          _log(
            '_syncFromAuthState aborted after expired signOut (stale token)',
          );
          return;
        }
        _setState(
          status: AuthStatus.blocked,
          user: null,
          subscription: null,
          message:
              'Subscription expired on $expiredOn. Please renew your package.',
        );
        return;
      }

      final authSessionId = await _ensureAuthSession(user: user);
      if (token != _refreshToken) {
        _log(
          '_syncFromAuthState aborted after ensureAuthSession (stale token)',
        );
        return;
      }
      _log(
        '_syncFromAuthState authenticated uid=${user.uid} subscription=${subscription.id} session=$authSessionId expiry=${subscription.expiryDate.toIso8601String()}',
      );
      _setState(
        status: AuthStatus.authenticated,
        user: user,
        subscription: subscription,
        message: null,
      );
    } on SessionLimitExceededException catch (error) {
      _log('_syncFromAuthState session_limit_exceeded limit=${error.limit}');
      await _browserSessionService.clearSessionAndCache();
      await _releaseAuthSession(user: user);
      await _firebaseAuthService.signOut();
      if (token != _refreshToken) {
        _log(
          '_syncFromAuthState aborted after session limit signOut (stale token)',
        );
        return;
      }
      _setState(
        status: AuthStatus.blocked,
        user: null,
        subscription: null,
        message:
            'Reached maximum ${error.limit} active sessions for this account. Please logout from another device or wait for session expiry.',
      );
    } on FirebaseAuthException catch (error) {
      _log(
        '_syncFromAuthState FirebaseAuthException code=${error.code} message=${error.message}',
      );
      _setState(
        status: AuthStatus.error,
        user: null,
        subscription: null,
        message: error.message ?? 'Unable to validate account.',
      );
    } on FirebaseException catch (error) {
      _log(
        '_syncFromAuthState FirebaseException code=${error.code} message=${error.message}',
      );
      final message = switch (error.code) {
        'permission-denied' =>
          'Subscription access denied. Please deploy Firestore rules for subscriptions and try again.',
        'unavailable' =>
          'Subscription service unavailable. Please check internet and try again.',
        _ => error.message ?? 'Unable to validate subscription.',
      };
      _setState(
        status: AuthStatus.error,
        user: null,
        subscription: null,
        message: message,
      );
    } catch (error) {
      _log('_syncFromAuthState exception reason=$reason error=$error');
      _setState(
        status: AuthStatus.error,
        user: null,
        subscription: null,
        message: 'Unable to validate subscription ($reason): $error',
      );
    }
  }

  Future<String> _ensureAuthSession({required User user}) async {
    final existingSessionId = await _localSessionStore.readSessionId(user.uid);
    try {
      final activeSession = await _authSessionService.ensureActiveSession(
        user: user,
        existingSessionId: existingSessionId,
      );
      await _localSessionStore.writeSessionId(user.uid, activeSession.id);
      _activeAuthSessionId = activeSession.id;
      _log('_ensureAuthSession active session=${activeSession.id}');
      return activeSession.id;
    } on SessionExpiredException {
      _log('_ensureAuthSession existing session expired, recreating');
      await _localSessionStore.clearSessionId(user.uid);
    } on SessionInvalidException {
      _log('_ensureAuthSession existing session invalid, recreating');
      await _localSessionStore.clearSessionId(user.uid);
    }

    final recreatedSession = await _authSessionService.ensureActiveSession(
      user: user,
    );
    await _localSessionStore.writeSessionId(user.uid, recreatedSession.id);
    _activeAuthSessionId = recreatedSession.id;
    _log('_ensureAuthSession recreated session=${recreatedSession.id}');
    return recreatedSession.id;
  }

  Future<void> _releaseAuthSession({required User? user}) async {
    if (user == null) {
      _activeAuthSessionId = null;
      return;
    }

    final uid = user.uid;
    final knownSessionId =
        _activeAuthSessionId ?? await _localSessionStore.readSessionId(uid);
    final sessionId = (knownSessionId ?? '').trim();
    if (sessionId.isNotEmpty) {
      try {
        await _authSessionService.revokeSession(sessionId);
        _log('_releaseAuthSession revoked session=$sessionId');
      } catch (error) {
        _log(
          '_releaseAuthSession revoke failed session=$sessionId error=$error',
        );
      }
    }

    try {
      await _localSessionStore.clearSessionId(uid);
    } catch (error) {
      _log('_releaseAuthSession clear local failed uid=$uid error=$error');
    }
    _activeAuthSessionId = null;
  }

  void _setState({
    required AuthStatus status,
    User? user,
    SubscriptionRecord? subscription,
    String? message,
  }) {
    _status = status;
    _currentUser = user;
    _currentSubscription = subscription;
    _message = message;
    _log(
      '_setState status=$status user=${user?.uid ?? "null"} hasSubscription=${subscription != null} message=${message ?? "-"}',
    );
    notifyListeners();
  }

  String _formatYyyyMmDd(DateTime dateTime) {
    final local = dateTime.toLocal();
    final yyyy = local.year.toString().padLeft(4, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd';
  }

  void _log(String message) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('[GO_PLAY-AuthController] $message');
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    super.dispose();
  }
}
