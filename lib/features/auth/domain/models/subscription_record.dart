class SubscriptionRecord {
  const SubscriptionRecord({
    required this.id,
    required this.email,
    required this.emailLower,
    required this.uid,
    required this.expiryDate,
    required this.expiryDateText,
    required this.status,
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
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String updatedBy;
  final String source;

  bool get isExpired => !expiryDate.toUtc().isAfter(DateTime.now().toUtc());
  bool get isActive => status.toLowerCase() == 'active' && !isExpired;
}
