class SessionPackageStatus {
  const SessionPackageStatus._({
    required this.remainingDays,
    required this.expiresAtUtc,
  });

  factory SessionPackageStatus.fromExpiresAt(DateTime? expiresAtUtc) {
    if (expiresAtUtc == null) {
      return const SessionPackageStatus._(remainingDays: 0, expiresAtUtc: null);
    }

    final normalizedExpiry = expiresAtUtc.toUtc();
    final nowUtc = DateTime.now().toUtc();
    if (!normalizedExpiry.isAfter(nowUtc)) {
      return SessionPackageStatus._(
        remainingDays: 0,
        expiresAtUtc: normalizedExpiry,
      );
    }

    final remainingMs = normalizedExpiry.difference(nowUtc).inMilliseconds;
    final remainingDays = (remainingMs / Duration.millisecondsPerDay).ceil();
    return SessionPackageStatus._(
      remainingDays: remainingDays,
      expiresAtUtc: normalizedExpiry,
    );
  }

  final int remainingDays;
  final DateTime? expiresAtUtc;

  bool get hasPackage => remainingDays > 0;
  String get tabStatusLabel => hasPackage ? 'PREMIUM' : 'NO PACKAGE';
  String get remainingDaysLabel =>
      hasPackage ? 'เหลือ $remainingDays วัน' : 'หมดแพ็กเกจ';
}
