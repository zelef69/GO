enum SessionValidationCode {
  ok,
  expired,
  blocked,
  deviceRevoked,
  versionMismatch,
  sessionNotFound,
}

class SessionValidationResult {
  const SessionValidationResult({
    required this.code,
    this.expireAt,
    this.sessionId,
    this.version,
  });

  final SessionValidationCode code;
  final DateTime? expireAt;
  final String? sessionId;
  final int? version;

  bool get isOk => code == SessionValidationCode.ok;
}

class DeviceSessionRegistrationResult {
  const DeviceSessionRegistrationResult({
    required this.sessionId,
    required this.expireAt,
    required this.maxDevices,
    required this.version,
  });

  final String sessionId;
  final DateTime? expireAt;
  final int? maxDevices;
  final int? version;
}
