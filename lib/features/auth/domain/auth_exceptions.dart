class SessionLimitExceededException implements Exception {
  SessionLimitExceededException({required this.limit});

  final int limit;

  @override
  String toString() => 'SessionLimitExceededException(limit: $limit)';
}

class SessionExpiredException implements Exception {
  @override
  String toString() => 'SessionExpiredException()';
}

class SessionInvalidException implements Exception {
  @override
  String toString() => 'SessionInvalidException()';
}

class SessionBlockedException implements Exception {
  @override
  String toString() => 'SessionBlockedException()';
}

class SessionFunctionException implements Exception {
  SessionFunctionException({
    required this.code,
    required this.message,
    this.details,
  });

  final String code;
  final String message;
  final Object? details;

  @override
  String toString() =>
      'SessionFunctionException(code: $code, message: $message)';
}
