class AuthConfig {
  const AuthConfig._();

  static const int maxSessionsPerEmail = 10;
  static const Duration sessionTtl = Duration(days: 30);
  static const String sessionsCollectionPath = 'userSessions';
  static const String subscriptionsCollectionPath = 'subscriptions';
  static const Duration initialSubscriptionDuration = Duration(days: 30);
}
