class AuthConfig {
  const AuthConfig._();

  static const int defaultMaxDevices = 10;
  static const String usersCollectionPath = 'users';
  static const String functionsRegion = 'us-central1';

  static const String registerDeviceSessionFn = 'registerDeviceSession';
  static const String validateDeviceSessionFn = 'validateDeviceSession';
  static const String heartbeatDeviceSessionFn = 'heartbeatDeviceSession';
  static const String logoutDeviceSessionFn = 'logoutDeviceSession';
  static const String addSubscriptionDaysFn = 'addSubscriptionDays';
  static const String forceLogoutAllDevicesFn = 'forceLogoutAllDevices';

  static const Duration signInTimeout = Duration(seconds: 45);
  static const Duration heartbeatInterval = Duration(minutes: 3);
}
