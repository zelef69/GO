import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../app/config/auth_config.dart';
import '../domain/auth_exceptions.dart';
import '../domain/models/device_identity.dart';
import '../domain/models/device_session_result.dart';

class AuthSessionService {
  AuthSessionService({FirebaseFunctions? functions})
    : _functions =
          functions ??
          FirebaseFunctions.instanceFor(region: AuthConfig.functionsRegion);

  final FirebaseFunctions _functions;
  static const Duration _callTimeout = Duration(seconds: 20);
  bool _functionsUnavailable = false;

  Future<DeviceSessionRegistrationResult> registerDeviceSession({
    required User user,
    required DeviceIdentity deviceIdentity,
    String? existingSessionId,
  }) async {
    if (_functionsUnavailable) {
      return _fallbackRegister(
        deviceIdentity: deviceIdentity,
        existingSessionId: existingSessionId,
      );
    }
    final callable = _functions.httpsCallable(AuthConfig.registerDeviceSessionFn);
    final payload = <String, dynamic>{
      'sessionId': existingSessionId ?? '',
      'deviceId': deviceIdentity.deviceId,
      'deviceName': deviceIdentity.deviceName,
      'platform': deviceIdentity.platform,
      'model': deviceIdentity.model,
      'appVersion': deviceIdentity.appVersion,
    };
    _log(
      'registerDeviceSession uid=${user.uid} deviceId=${deviceIdentity.deviceId}',
    );
    try {
      final result = await callable.call(payload).timeout(_callTimeout);
      final data = _asMap(result.data);
      final sessionId = (data['sessionId'] ?? '').toString().trim();
      if (sessionId.isEmpty) {
        throw SessionFunctionException(
          code: 'INVALID_RESPONSE',
          message: 'registerDeviceSession returned empty sessionId.',
          details: data,
        );
      }
      return DeviceSessionRegistrationResult(
        sessionId: sessionId,
        expireAt: _toDateTime(data['expireAt']),
        maxDevices: _toIntOrNull(data['maxDevices']),
        version: _toIntOrNull(data['version']),
      );
    } on FirebaseFunctionsException catch (error) {
      if (_isFunctionNotFound(error)) {
        _functionsUnavailable = true;
        _log(
          'registerDeviceSession fallback enabled (function not found) code=${error.code}',
        );
        return _fallbackRegister(
          deviceIdentity: deviceIdentity,
          existingSessionId: existingSessionId,
        );
      }
      _throwMappedException(error);
    }
  }

  Future<SessionValidationResult> validateDeviceSession({
    required User user,
    required String sessionId,
    required String deviceId,
  }) async {
    if (_functionsUnavailable) {
      return SessionValidationResult(
        code: SessionValidationCode.ok,
        sessionId: sessionId,
      );
    }
    final callable = _functions.httpsCallable(AuthConfig.validateDeviceSessionFn);
    final payload = <String, dynamic>{
      'sessionId': sessionId,
      'deviceId': deviceId,
    };
    _log('validateDeviceSession uid=${user.uid} sessionId=$sessionId');
    try {
      final result = await callable.call(payload).timeout(_callTimeout);
      final data = _asMap(result.data);
      final code = _validationCodeFromServer(data['resultCode']);
      return SessionValidationResult(
        code: code,
        expireAt: _toDateTime(data['expireAt']),
        sessionId: (data['sessionId'] ?? '').toString().trim().isEmpty
            ? sessionId
            : (data['sessionId'] ?? '').toString().trim(),
        version: _toIntOrNull(data['version']),
      );
    } on FirebaseFunctionsException catch (error) {
      if (_isFunctionNotFound(error)) {
        _functionsUnavailable = true;
        _log(
          'validateDeviceSession fallback enabled (function not found) code=${error.code}',
        );
        return SessionValidationResult(
          code: SessionValidationCode.ok,
          sessionId: sessionId,
        );
      }
      _throwMappedException(error);
    }
  }

  Future<void> heartbeatDeviceSession({
    required User user,
    required String sessionId,
    required DeviceIdentity deviceIdentity,
  }) async {
    if (_functionsUnavailable) {
      return;
    }
    final callable = _functions.httpsCallable(AuthConfig.heartbeatDeviceSessionFn);
    final payload = <String, dynamic>{
      'sessionId': sessionId,
      'deviceId': deviceIdentity.deviceId,
      'platform': deviceIdentity.platform,
      'model': deviceIdentity.model,
      'appVersion': deviceIdentity.appVersion,
    };
    _log('heartbeatDeviceSession uid=${user.uid} sessionId=$sessionId');
    try {
      await callable.call(payload).timeout(_callTimeout);
    } on FirebaseFunctionsException catch (error) {
      if (_isFunctionNotFound(error)) {
        _functionsUnavailable = true;
        _log(
          'heartbeatDeviceSession fallback enabled (function not found) code=${error.code}',
        );
        return;
      }
      _throwMappedException(error);
    }
  }

  Future<void> logoutDeviceSession({
    required User user,
    required String sessionId,
    required String deviceId,
  }) async {
    if (_functionsUnavailable) {
      return;
    }
    final callable = _functions.httpsCallable(AuthConfig.logoutDeviceSessionFn);
    final payload = <String, dynamic>{
      'sessionId': sessionId,
      'deviceId': deviceId,
    };
    _log('logoutDeviceSession uid=${user.uid} sessionId=$sessionId');
    try {
      await callable.call(payload).timeout(_callTimeout);
    } on FirebaseFunctionsException catch (error) {
      if (_isFunctionNotFound(error)) {
        _functionsUnavailable = true;
        _log(
          'logoutDeviceSession fallback enabled (function not found) code=${error.code}',
        );
        return;
      }
      final appCode = _readAppCode(error);
      if (appCode == 'SESSION_NOT_FOUND') {
        return;
      }
      _throwMappedException(error);
    }
  }

  DeviceSessionRegistrationResult _fallbackRegister({
    required DeviceIdentity deviceIdentity,
    String? existingSessionId,
  }) {
    final resolvedSessionId = (existingSessionId ?? '').trim().isNotEmpty
        ? existingSessionId!.trim()
        : 'local_${DateTime.now().millisecondsSinceEpoch}_${deviceIdentity.deviceId.hashCode.abs()}';
    return DeviceSessionRegistrationResult(
      sessionId: resolvedSessionId,
      expireAt: null,
      maxDevices: AuthConfig.defaultMaxDevices,
      version: 1,
    );
  }

  bool _isFunctionNotFound(FirebaseFunctionsException error) {
    final normalizedCode = error.code.toLowerCase();
    if (normalizedCode == 'not-found' || normalizedCode == 'unimplemented') {
      return true;
    }
    final message = (error.message ?? '').toLowerCase();
    return message.contains('not_found') || message.contains('not found');
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, v) => MapEntry(key.toString(), v));
    }
    return const <String, dynamic>{};
  }

  SessionValidationCode _validationCodeFromServer(dynamic rawCode) {
    final normalized = rawCode?.toString().trim().toUpperCase() ?? '';
    return switch (normalized) {
      'OK' => SessionValidationCode.ok,
      'EXPIRED' => SessionValidationCode.expired,
      'BLOCKED' => SessionValidationCode.blocked,
      'DEVICE_REVOKED' => SessionValidationCode.deviceRevoked,
      'VERSION_MISMATCH' => SessionValidationCode.versionMismatch,
      'SESSION_NOT_FOUND' => SessionValidationCode.sessionNotFound,
      _ => SessionValidationCode.sessionNotFound,
    };
  }

  Never _throwMappedException(FirebaseFunctionsException error) {
    final appCode = _readAppCode(error);
    switch (appCode) {
      case 'DEVICE_LIMIT_EXCEEDED':
        throw SessionLimitExceededException(limit: _readLimit(error));
      case 'EXPIRED':
        throw SessionExpiredException();
      case 'BLOCKED':
        throw SessionBlockedException();
      case 'SESSION_NOT_FOUND':
      case 'DEVICE_REVOKED':
      case 'VERSION_MISMATCH':
        throw SessionInvalidException();
      default:
        throw SessionFunctionException(
          code: appCode.isEmpty ? error.code : appCode,
          message: error.message ?? 'Cloud function call failed.',
          details: error.details,
        );
    }
  }

  String _readAppCode(FirebaseFunctionsException error) {
    final details = error.details;
    if (details is Map) {
      final dynamic raw = details['code'];
      if (raw != null) {
        final code = raw.toString().trim().toUpperCase();
        if (code.isNotEmpty) {
          return code;
        }
      }
    }
    return '';
  }

  int _readLimit(FirebaseFunctionsException error) {
    final details = error.details;
    if (details is Map) {
      final dynamic maxDevices = details['maxDevices'];
      if (maxDevices is num) {
        return maxDevices.toInt();
      }
      if (maxDevices is String) {
        final parsed = int.tryParse(maxDevices);
        if (parsed != null && parsed > 0) {
          return parsed;
        }
      }
    }
    return AuthConfig.defaultMaxDevices;
  }

  DateTime? _toDateTime(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value)?.toUtc();
    }
    return null;
  }

  int? _toIntOrNull(dynamic value) {
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  void _log(String message) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('[GO_PLAY-SessionFn] $message');
  }
}
