class AppConfig {
  const AppConfig._();

  static const String appTitle = 'GO_PLAY YouTube Browser';
  static const String filterAssetPath = 'assets/filters/basic.txt';
  static const String defaultFilterRegion = 'global';
  static const Map<String, String> remoteFilterListUrls = <String, String>{};
  static const Duration remoteFilterRefreshInterval = Duration(hours: 12);
  static final Uri homeUri = Uri.https('m.youtube.com');
}
