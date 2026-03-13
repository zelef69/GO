class DeviceIdentity {
  const DeviceIdentity({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.model,
    required this.appVersion,
  });

  final String deviceId;
  final String deviceName;
  final String platform;
  final String model;
  final String appVersion;
}
