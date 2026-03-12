class AuthSession {
  const AuthSession({
    required this.id,
    required this.uid,
    required this.email,
    required this.createdAt,
    required this.lastSeenAt,
    required this.expiresAt,
    required this.status,
  });

  final String id;
  final String uid;
  final String email;
  final DateTime? createdAt;
  final DateTime? lastSeenAt;
  final DateTime expiresAt;
  final String status;

  bool get isActive => status == 'active';
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
