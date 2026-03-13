import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../app/config/auth_config.dart';
import '../../services/security_service.dart';
import '../session/session_service.dart';
import 'data/auth_session_service.dart';
import 'data/device_id_service.dart';
import 'data/firebase_auth_service.dart';
import 'data/local_session_store.dart';
import 'data/subscription_service.dart';
import 'domain/auth_exceptions.dart';
import 'domain/models/device_identity.dart';
import 'domain/models/device_session_result.dart';
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

class AuthController extends ChangeNotifier with WidgetsBindingObserver {
  AuthController({
    required FirebaseAuthService firebaseAuthService,
    required SubscriptionService subscriptionService,
    required AuthSessionService authSessionService,
    required LocalSessionStore localSessionStore,
    required SessionService browserSessionService,
    required DeviceIdService deviceIdService,
  }) : _firebaseAuthService = firebaseAuthService,
       _subscriptionService = subscriptionService,
       _authSessionService = authSessionService,
       _localSessionStore = localSessionStore,
       _browserSessionService = browserSessionService,
       _deviceIdService = deviceIdService;

  final FirebaseAuthService _firebaseAuthService;
  final SubscriptionService _subscriptionService;
  final AuthSessionService _authSessionService;
  final LocalSessionStore _localSessionStore;
  final SessionService _browserSessionService;
  final DeviceIdService _deviceIdService;
  static const Duration _signInTimeout = AuthConfig.signInTimeout;

  StreamSubscription<User?>? _authStateSubscription;
  Timer? _heartbeatTimer;

  bool _initialized = false;
  bool _sessionCheckInFlight = false;
  int _refreshToken = 0;

  String? _activeAuthSessionId;
  String? _pendingBlockedMessage;
  DeviceIdentity? _cachedDeviceIdentity;

  AuthStatus _status = AuthStatus.initializing;
  User? _currentUser;
  SubscriptionRecord? _currentSubscription;
  String? _message;

  AuthStatus get status => _status;
  User? get currentUser => _currentUser;
  SubscriptionRecord? get currentSubscription => _currentSubscription;
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
    WidgetsBinding.instance.addObserver(this);
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
      await _syncFromAuthState(reason: 'google_sign_in');
    } on TimeoutException {
      _setState(
        status: AuthStatus.error,
        message: 'Google sign-in timed out. Please check your network.',
      );
    } on FirebaseAuthException catch (error) {
      _setState(
        status: AuthStatus.error,
        message: error.message ?? 'Google sign-in failed.',
      );
    } catch (error) {
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
    await _logoutDeviceSession(user: signedInUser);
    await _firebaseAuthService.signOut();
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
      final blockedMessage = _pendingBlockedMessage;
      _pendingBlockedMessage = null;
      _setState(
        status: blockedMessage == null
            ? AuthStatus.unauthenticated
            : AuthStatus.blocked,
        user: null,
        subscription: null,
        message: blockedMessage,
      );
      return;
    }

    _setState(status: AuthStatus.checkingSession, user: user, message: null);
    if (token != _refreshToken) {
      return;
    }

    try {
      final deviceIdentity = await _resolveDeviceIdentity();
      if (token != _refreshToken) {
        return;
      }
      final existingSessionId = await _localSessionStore.readSessionId(user.uid);
      final session = await _authSessionService.registerDeviceSession(
        user: user,
        deviceIdentity: deviceIdentity,
        existingSessionId: existingSessionId,
      );
      if (token != _refreshToken) {
        return;
      }
      await _localSessionStore.writeSessionId(user.uid, session.sessionId);
      _activeAuthSessionId = session.sessionId;

      final validation = await _authSessionService.validateDeviceSession(
        user: user,
        sessionId: session.sessionId,
        deviceId: deviceIdentity.deviceId,
      );
      if (token != _refreshToken) {
        return;
      }
      if (
          !validation.isOk &&
          validation.code != SessionValidationCode.expired) {
        await _handleValidationFailure(
          user: user,
          validation: validation,
          reason: reason,
        );
        return;
      }

      final subscription = await _subscriptionService.ensureSubscription(
        user: user,
      );
      if (token != _refreshToken) {
        return;
      }
      _setState(
        status: AuthStatus.authenticated,
        user: user,
        subscription: subscription,
        message: null,
      );
      unawaited(_validateCurrentSession(reason: 'post_auth'));
    } on SessionLimitExceededException catch (error) {
      await _forceSignOutToLogin(
        user: user,
        message:
            'เกินจำนวนอุปกรณ์ที่อนุญาต (${error.limit}) กรุณาออกจากระบบอุปกรณ์อื่นก่อน',
      );
    } on SessionExpiredException {
      _log('_syncFromAuthState expired ignored user=${user.uid}');
      final subscription = await _subscriptionService.getCurrentSubscription(
        user: user,
      );
      if (subscription != null) {
        _setState(
          status: AuthStatus.authenticated,
          user: user,
          subscription: subscription,
          message: null,
        );
      }
    } on SessionBlockedException {
      await _forceSignOutToLogin(
        user: user,
        message: 'บัญชีถูกระงับการใช้งาน',
      );
    } on SessionInvalidException {
      await _forceSignOutToLogin(
        user: user,
        message: 'กรุณาเข้าสู่ระบบใหม่',
      );
    } on SessionFunctionException catch (error) {
      _setState(
        status: AuthStatus.error,
        user: null,
        subscription: null,
        message: error.message,
      );
    } on FirebaseAuthException catch (error) {
      _setState(
        status: AuthStatus.error,
        user: null,
        subscription: null,
        message: error.message ?? 'Unable to validate account.',
      );
    } on FirebaseException catch (error) {
      _setState(
        status: AuthStatus.error,
        user: null,
        subscription: null,
        message: error.message ?? 'Unable to validate account session.',
      );
    } catch (error) {
      _setState(
        status: AuthStatus.error,
        user: null,
        subscription: null,
        message: 'Unable to validate session ($reason): $error',
      );
    }
  }

  Future<void> _validateCurrentSession({required String reason}) async {
    if (_sessionCheckInFlight || _status != AuthStatus.authenticated) {
      return;
    }
    final user = _firebaseAuthService.currentUser;
    if (user == null) {
      return;
    }
    _sessionCheckInFlight = true;
    try {
      final sessionId = await _resolveSessionId(user.uid);
      if (sessionId == null) {
        await _forceSignOutToLogin(
          user: user,
          message: 'กรุณาเข้าสู่ระบบใหม่',
        );
        return;
      }
      final deviceIdentity = await _resolveDeviceIdentity();
      final validation = await _authSessionService.validateDeviceSession(
        user: user,
        sessionId: sessionId,
        deviceId: deviceIdentity.deviceId,
      );
      if (
          !validation.isOk &&
          validation.code != SessionValidationCode.expired) {
        await _handleValidationFailure(
          user: user,
          validation: validation,
          reason: reason,
        );
        return;
      }
      final subscription = await _subscriptionService.getCurrentSubscription(
        user: user,
      );
      if (subscription != null &&
          _status == AuthStatus.authenticated &&
          _currentUser?.uid == user.uid) {
        _setState(
          status: AuthStatus.authenticated,
          user: user,
          subscription: subscription,
          message: null,
        );
      }
    } on SessionExpiredException {
      _log('_validateCurrentSession expired ignored user=${user.uid}');
    } on SessionBlockedException {
      await _forceSignOutToLogin(user: user, message: 'บัญชีถูกระงับการใช้งาน');
    } on SessionInvalidException {
      await _forceSignOutToLogin(user: user, message: 'กรุณาเข้าสู่ระบบใหม่');
    } catch (error) {
      _log('_validateCurrentSession reason=$reason error=$error');
    } finally {
      _sessionCheckInFlight = false;
    }
  }

  Future<void> _heartbeatTick() async {
    if (_status != AuthStatus.authenticated || _sessionCheckInFlight) {
      return;
    }
    final user = _firebaseAuthService.currentUser;
    if (user == null) {
      return;
    }
    _sessionCheckInFlight = true;
    try {
      final sessionId = await _resolveSessionId(user.uid);
      if (sessionId == null) {
        await _forceSignOutToLogin(
          user: user,
          message: 'กรุณาเข้าสู่ระบบใหม่',
        );
        return;
      }
      final deviceIdentity = await _resolveDeviceIdentity();
      await _authSessionService.heartbeatDeviceSession(
        user: user,
        sessionId: sessionId,
        deviceIdentity: deviceIdentity,
      );
      final validation = await _authSessionService.validateDeviceSession(
        user: user,
        sessionId: sessionId,
        deviceId: deviceIdentity.deviceId,
      );
      if (
          !validation.isOk &&
          validation.code != SessionValidationCode.expired) {
        await _handleValidationFailure(
          user: user,
          validation: validation,
          reason: 'heartbeat',
        );
      }
    } on SessionExpiredException {
      _log('_heartbeatTick expired ignored user=${user.uid}');
    } on SessionBlockedException {
      await _forceSignOutToLogin(user: user, message: 'บัญชีถูกระงับการใช้งาน');
    } on SessionInvalidException {
      await _forceSignOutToLogin(user: user, message: 'กรุณาเข้าสู่ระบบใหม่');
    } catch (error) {
      _log('_heartbeatTick error=$error');
    } finally {
      _sessionCheckInFlight = false;
    }
  }

  Future<void> _handleValidationFailure({
    required User user,
    required SessionValidationResult validation,
    required String reason,
  }) async {
    if (validation.code == SessionValidationCode.expired) {
      _log(
        '_handleValidationFailure expired ignored reason=$reason user=${user.uid}',
      );
      return;
    }

    final message = switch (validation.code) {
      SessionValidationCode.expired => 'บัญชีหมดอายุ',
      SessionValidationCode.blocked => 'บัญชีถูกระงับการใช้งาน',
      SessionValidationCode.deviceRevoked => 'อุปกรณ์นี้ถูกยกเลิกสิทธิ์',
      SessionValidationCode.versionMismatch ||
      SessionValidationCode.sessionNotFound => 'กรุณาเข้าสู่ระบบใหม่',
      SessionValidationCode.ok => 'กรุณาเข้าสู่ระบบใหม่',
    };
    _log(
      '_handleValidationFailure reason=$reason code=${validation.code} user=${user.uid}',
    );
    await _forceSignOutToLogin(user: user, message: message);
  }

  Future<void> _forceSignOutToLogin({
    required User user,
    required String message,
  }) async {
    _pendingBlockedMessage = message;
    await _browserSessionService.clearSessionAndCache();
    await _logoutDeviceSession(user: user);
    await _firebaseAuthService.signOut();
    _setState(
      status: AuthStatus.blocked,
      user: null,
      subscription: null,
      message: message,
    );
  }

  Future<void> _logoutDeviceSession({required User? user}) async {
    if (user == null) {
      _activeAuthSessionId = null;
      return;
    }
    final sessionId = await _resolveSessionId(user.uid);
    final deviceIdentity = await _resolveDeviceIdentity();
    if (sessionId != null) {
      try {
        await _authSessionService.logoutDeviceSession(
          user: user,
          sessionId: sessionId,
          deviceId: deviceIdentity.deviceId,
        );
      } catch (error) {
        _log('_logoutDeviceSession remote failed error=$error');
      }
    }
    await _localSessionStore.clearSessionId(user.uid);
    _activeAuthSessionId = null;
  }

  Future<String?> _resolveSessionId(String uid) async {
    final active = (_activeAuthSessionId ?? '').trim();
    if (active.isNotEmpty) {
      return active;
    }
    final stored = (await _localSessionStore.readSessionId(uid) ?? '').trim();
    if (stored.isNotEmpty) {
      _activeAuthSessionId = stored;
      return stored;
    }
    return null;
  }

  Future<DeviceIdentity> _resolveDeviceIdentity() async {
    final cached = _cachedDeviceIdentity;
    if (cached != null) {
      return cached;
    }
    final resolved = await _deviceIdService.getIdentity();
    _cachedDeviceIdentity = resolved;
    return resolved;
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

    if (_status == AuthStatus.authenticated &&
        _currentUser != null &&
        _currentSubscription != null) {
      _startHeartbeat();
    } else {
      _stopHeartbeat();
    }

    _log(
      '_setState status=$status user=${user?.uid ?? "null"} hasSubscription=${subscription != null} message=${message ?? "-"}',
    );
    notifyListeners();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(AuthConfig.heartbeatInterval, (_) {
      unawaited(_heartbeatTick());
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _log(String message) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('[GO_PLAY-AuthController] $message');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_validateCurrentSession(reason: 'app_resumed'));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _authStateSubscription?.cancel();
    super.dispose();
  }
}
