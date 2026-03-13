class AppConfig {
  const AppConfig._();

  static const String appTitle = 'GO_PLAY YouTube Browser';
  static const String filterAssetPath = 'assets/filters/basic.txt';
  static const String braveListCatalogUrl =
      'https://raw.githubusercontent.com/brave/adblock-resources/master/filter_lists/list_catalog.json';
  static const String braveResourcesUrl =
      'https://raw.githubusercontent.com/brave/adblock-resources/master/dist/resources.json';
  static const String defaultFilterRegion = 'global';
  static const Map<String, String> remoteFilterListUrls = <String, String>{};
  static const Duration remoteFilterRefreshInterval = Duration(hours: 12);
  static final Uri homeUri = Uri.https('m.youtube.com');
}
