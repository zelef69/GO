class SubscriptionRecord {
  const SubscriptionRecord({
    required this.id,
    required this.email,
    required this.emailLower,
    required this.uid,
    required this.expiryDate,
    required this.expiryDateText,
    required this.status,
    required this.plan,
    required this.startAt,
    required this.maxDevices,
    required this.extraDays,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    required this.updatedBy,
    required this.source,
  });

  final String id;
  final String email;
  final String emailLower;
  final String uid;
  final DateTime expiryDate;
  final String expiryDateText;
  final String status;
  final String plan;
  final DateTime? startAt;
  final int? maxDevices;
  final int? extraDays;
  final int? version;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String updatedBy;
  final String source;

  bool get isExpired => !expiryDate.toUtc().isAfter(DateTime.now().toUtc());
  bool get isBlocked => status.toLowerCase() == 'blocked';
  bool get isActive => status.toLowerCase() == 'active' && !isExpired && !isBlocked;
}
