class UpdateManifest {
  const UpdateManifest({
    required this.appId,
    required this.channel,
    required this.latestVersionCode,
    required this.latestVersionName,
    required this.minSupportedVersionCode,
    required this.forceUpdate,
    required this.apkUrl,
    required this.apkSha256,
    required this.apkSizeBytes,
    required this.changelog,
    required this.publishedAt,
  });

  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    final appId = (json['appId'] ?? '').toString().trim();
    final channel = (json['channel'] ?? '').toString().trim();
    final latestVersionCode = _asInt(json['latestVersionCode']);
    final latestVersionName = (json['latestVersionName'] ?? '')
        .toString()
        .trim();
    final minSupportedVersionCode = _asInt(json['minSupportedVersionCode']);
    final forceUpdate = json['forceUpdate'] == true;
    final apkUrl = (json['apkUrl'] ?? '').toString().trim();
    final apkSha256 = (json['apkSha256'] ?? '').toString().trim().toLowerCase();
    final apkSizeBytes = _asInt(json['apkSizeBytes']);
    final changelog = (json['changelog'] is List)
        ? (json['changelog'] as List<dynamic>)
              .map((entry) => entry.toString().trim())
              .where((entry) => entry.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    final publishedAtRaw = (json['publishedAt'] ?? '').toString().trim();
    final publishedAt =
        DateTime.tryParse(publishedAtRaw)?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    if (appId.isEmpty) {
      throw const FormatException('manifest: appId is required');
    }
    if (latestVersionCode <= 0) {
      throw const FormatException('manifest: latestVersionCode must be > 0');
    }
    if (latestVersionName.isEmpty) {
      throw const FormatException('manifest: latestVersionName is required');
    }
    if (apkUrl.isEmpty) {
      throw const FormatException('manifest: apkUrl is required');
    }
    final apkUri = Uri.tryParse(apkUrl);
    if (apkUri == null || !apkUri.hasScheme || !apkUri.hasAuthority) {
      throw const FormatException('manifest: apkUrl is invalid');
    }
    final hashPattern = RegExp(r'^[a-f0-9]{64}$');
    if (!hashPattern.hasMatch(apkSha256)) {
      throw const FormatException('manifest: apkSha256 must be 64-char hex');
    }

    return UpdateManifest(
      appId: appId,
      channel: channel,
      latestVersionCode: latestVersionCode,
      latestVersionName: latestVersionName,
      minSupportedVersionCode: minSupportedVersionCode,
      forceUpdate: forceUpdate,
      apkUrl: apkUrl,
      apkSha256: apkSha256,
      apkSizeBytes: apkSizeBytes,
      changelog: changelog,
      publishedAt: publishedAt,
    );
  }

  final String appId;
  final String channel;
  final int latestVersionCode;
  final String latestVersionName;
  final int minSupportedVersionCode;
  final bool forceUpdate;
  final String apkUrl;
  final String apkSha256;
  final int apkSizeBytes;
  final List<String> changelog;
  final DateTime publishedAt;

  static int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value.trim()) ?? 0;
    }
    return 0;
  }
}
