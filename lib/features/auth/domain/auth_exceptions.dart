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
