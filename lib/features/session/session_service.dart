import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class SessionService {
  SessionService({
    CookieManager? cookieManager,
    WebStorageManager? webStorageManager,
  })  : _cookieManager = cookieManager ?? CookieManager.instance(),
        _webStorageManager = webStorageManager ?? WebStorageManager.instance();

  final CookieManager _cookieManager;
  final WebStorageManager _webStorageManager;

  Future<void> clearSessionAndCache() async {
    await _cookieManager.deleteAllCookies();
    await _webStorageManager.deleteAllData();
    await InAppWebViewController.clearAllCache();
  }
}
