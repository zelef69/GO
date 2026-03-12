import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'adblock_config.dart';
import 'adblock_debug_logger.dart';
import 'adblock_manager.dart';
import 'cosmetic_filter_injector.dart';
import 'request_blocker.dart';
import 'scriptlet_injector.dart';

class WebViewAdblockIntegration {
  WebViewAdblockIntegration({
    required AdblockManager manager,
    required AdblockDebugLogger logger,
    required CosmeticFilterInjector cosmeticFilterInjector,
    required ScriptletInjector scriptletInjector,
    required AdblockConfig initialConfig,
  }) : _manager = manager,
       _logger = logger,
       _cosmeticFilterInjector = cosmeticFilterInjector,
       _scriptletInjector = scriptletInjector,
       _config = initialConfig {
    _cosmeticFilterInjector.setConfig(initialConfig);
    _scriptletInjector.setConfig(initialConfig);
  }

  final AdblockManager _manager;
  final AdblockDebugLogger _logger;
  final CosmeticFilterInjector _cosmeticFilterInjector;
  final ScriptletInjector _scriptletInjector;

  AdblockConfig _config;
  InAppWebViewController? _controller;
  Uri? _currentPageUri;
  bool _serviceWorkerAttached = false;
  int _serviceWorkerBlockCount = 0;
  static const int _maxServiceWorkerBlockLogs = 80;

  Uri? get currentPageUri => _currentPageUri;

  void updateConfig(AdblockConfig config) {
    _config = config;
    _cosmeticFilterInjector.setConfig(config);
    _scriptletInjector.setConfig(config);
  }

  Future<void> attachWebView(InAppWebViewController controller) async {
    _controller = controller;
    await _configureServiceWorkerInterception();
  }

  void onMainFrameChanged(Uri? uri) {
    _currentPageUri = uri;
    _manager.onMainFrameChanged(uri);
  }

  Future<AdblockDecision> evaluateRequest({
    required Uri uri,
    required String resourceType,
    Uri? sourceUri,
    bool fromServiceWorker = false,
  }) {
    final context = AdblockRequestContext(
      uri: uri,
      resourceType: resourceType,
      sourceUrl: sourceUri,
      fromServiceWorker: fromServiceWorker,
    );
    return _manager.evaluate(context);
  }

  Future<void> syncRuntimeLayers({bool force = false}) async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    await _cosmeticFilterInjector.injectIfNeeded(
      controller,
      pageUri: _currentPageUri,
      force: force,
    );
    await _scriptletInjector.injectIfNeeded(
      controller,
      pageUri: _currentPageUri,
      force: force,
    );
  }

  Future<void> onPageStarted(Uri? uri) async {
    onMainFrameChanged(uri);
    await syncRuntimeLayers();
  }

  Future<void> onPageFinished(Uri? uri) async {
    onMainFrameChanged(uri);
    await syncRuntimeLayers(force: true);
  }

  Future<void> dispose() async {
    _controller = null;
    if (_serviceWorkerAttached && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await ServiceWorkerController.instance().setServiceWorkerClient(null);
      } catch (_) {}
    }
    _serviceWorkerAttached = false;
    _serviceWorkerBlockCount = 0;
  }

  Future<void> _configureServiceWorkerInterception() async {
    if (!_config.serviceWorkerInterceptionEnabled) {
      _logger.log('service worker interception disabled by config');
      return;
    }
    if (_serviceWorkerAttached || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    bool featureSupported = false;
    try {
      featureSupported = await WebViewFeature.isFeatureSupported(
        WebViewFeature.SERVICE_WORKER_SHOULD_INTERCEPT_REQUEST,
      );
    } catch (_) {
      featureSupported = false;
    }
    if (!featureSupported) {
      _logger.log('service worker interception not supported');
      return;
    }

    try {
      await ServiceWorkerController.instance().setServiceWorkerClient(
        ServiceWorkerClient(
          shouldInterceptRequest: (request) async {
            if (!_config.enabled) {
              return null;
            }
            final uri = Uri.tryParse(request.url.toString());
            if (uri == null) {
              return null;
            }
            final sourceUri = _sourceUriFromHeaders(request.headers);
            final decision = await evaluateRequest(
              uri: uri,
              resourceType: _resourceTypeFromRequest(request),
              sourceUri: sourceUri ?? _currentPageUri,
              fromServiceWorker: true,
            );
            if (!decision.blocked) {
              return null;
            }
            if (_serviceWorkerBlockCount < _maxServiceWorkerBlockLogs) {
              _serviceWorkerBlockCount += 1;
              _logger.log(
                'service worker blocked host=${uri.host} path=${uri.path} reason=${decision.reason}',
              );
            }
            return WebResourceResponse(
              contentType: 'text/plain',
              data: Uint8List(0),
              statusCode: 204,
              reasonPhrase: 'No Content',
              headers: const <String, String>{'Cache-Control': 'no-store'},
            );
          },
        ),
      );
      _serviceWorkerAttached = true;
      _logger.log('service worker interception enabled');
    } catch (_) {
      _logger.log('service worker interception setup failed');
    }
  }

  Uri? _sourceUriFromHeaders(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) {
      return null;
    }
    for (final entry in headers.entries) {
      final key = entry.key.toLowerCase();
      if (key != 'referer' && key != 'referrer') {
        continue;
      }
      final value = entry.value.trim();
      if (value.isEmpty) {
        continue;
      }
      return Uri.tryParse(value);
    }
    return null;
  }

  String _resourceTypeFromRequest(WebResourceRequest request) {
    final headers = request.headers ?? const <String, String>{};
    final secFetchDest =
        (headers['Sec-Fetch-Dest'] ?? headers['sec-fetch-dest'] ?? '').toLowerCase();
    switch (secFetchDest) {
      case 'script':
        return 'script';
      case 'style':
        return 'stylesheet';
      case 'image':
        return 'image';
      case 'font':
        return 'font';
      case 'video':
      case 'audio':
      case 'track':
        return 'media';
      case 'iframe':
      case 'frame':
        return 'subdocument';
      case 'document':
        return 'document';
      case 'empty':
        return 'xmlhttprequest';
      default:
        return 'other';
    }
  }
}
