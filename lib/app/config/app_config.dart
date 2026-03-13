class AppConfig {
  const AppConfig._();

  static const String appTitle = 'GO_PLAY YouTube Browser';
  static const String appVersion = String.fromEnvironment(
    'GO_PLAY_APP_VERSION',
    defaultValue: '0.0.2-beta+2',
  );
  static const String latestAppVersion = String.fromEnvironment(
    'GO_PLAY_LATEST_APP_VERSION',
    defaultValue: '',
  );
  static const String updateUrl = String.fromEnvironment(
    'GO_PLAY_UPDATE_URL',
    defaultValue: '',
  );
  static const String updateManifestUrl = String.fromEnvironment(
    'GO_PLAY_UPDATE_MANIFEST_URL',
    defaultValue: '',
  );
  static const String updateSource = String.fromEnvironment(
    'GO_PLAY_UPDATE_SOURCE',
    defaultValue: 'auto',
  );
  static const String updateFirestoreCollection = String.fromEnvironment(
    'GO_PLAY_UPDATE_FIRESTORE_COLLECTION',
    defaultValue: 'app_updates',
  );
  static const String updateFirestoreDocument = String.fromEnvironment(
    'GO_PLAY_UPDATE_FIRESTORE_DOCUMENT',
    defaultValue: 'android',
  );
  static const String updateAppId = String.fromEnvironment(
    'GO_PLAY_UPDATE_APP_ID',
    defaultValue: 'com.example.go_play',
  );
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
