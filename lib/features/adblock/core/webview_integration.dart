import 'dart:convert';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../adblock_engine_bridge.dart';
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
  final LinkedHashMap<String, DateTime> _adSignalStates =
      LinkedHashMap<String, DateTime>();
  final LinkedHashMap<String, DateTime> _stallSignalStates =
      LinkedHashMap<String, DateTime>();
  String _mainFrameSignalKey = 'global';
  static const int _maxServiceWorkerBlockLogs = 80;
  static const int _maxCosmeticDomSignals = 480;
  static const Duration _adSignalTtl = Duration(milliseconds: 2400);
  static const Duration _stallSignalTtl = Duration(milliseconds: 2600);
  static const int _maxSignalStateEntries = 420;

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
    final previousSignalKey = _mainFrameSignalKey;
    final nextSignalKey = _requestSignalKeyFor(uri: uri);
    if (previousSignalKey != nextSignalKey) {
      clearSignalState(reason: 'main_frame_changed');
    }
    _mainFrameSignalKey = nextSignalKey;
    _currentPageUri = uri;
    _manager.onMainFrameChanged(uri);
  }

  void clearSignalState({String reason = 'manual'}) {
    if (_adSignalStates.isEmpty && _stallSignalStates.isEmpty) {
      return;
    }
    _adSignalStates.clear();
    _stallSignalStates.clear();
    _logger.log('signal_state cleared reason=$reason');
  }

  void updatePlaybackDebugSignal(Map<String, dynamic> payload, {Uri? pageUri}) {
    final signalKey = _requestSignalKeyFor(
      uri: pageUri ?? _currentPageUri,
      fallbackVideoId: payload['videoId']?.toString().trim(),
    );
    if (signalKey == 'global') {
      return;
    }

    final adShowing = payload['adShowing'] == true;
    final adInterrupting = payload['adInterrupting'] == true;
    final hasAdOverlay = payload['hasAdOverlay'] == true;
    if (adShowing || adInterrupting || hasAdOverlay) {
      _setSignal(_adSignalStates, signalKey, ttl: _adSignalTtl);
    }

    final eventName = (payload['event'] ?? '').toString().trim().toLowerCase();
    final readyState = _toInt(payload['readyState']);
    final networkState = _toInt(payload['networkState']);
    final stallLikeEvent =
        eventName == 'video:waiting' ||
        eventName == 'video:emptied' ||
        eventName == 'video:loadstart';
    final looksStalled =
        stallLikeEvent &&
        readyState <= 0 &&
        (networkState == 0 || networkState == 2 || networkState == 3);
    final recovered =
        eventName == 'video:playing' ||
        eventName == 'video:canplay' ||
        eventName == 'video:canplaythrough' ||
        readyState >= 2;

    if (looksStalled) {
      _setSignal(_stallSignalStates, signalKey, ttl: _stallSignalTtl);
    } else if (recovered) {
      _stallSignalStates.remove(signalKey);
    }

    _manager.onPlaybackDebugSignal(
      payload,
      pageUri: pageUri ?? _currentPageUri,
    );
  }

  String resolveRequestSignalKey(Uri uri, {Uri? sourceUri}) {
    return _requestSignalKeyFor(uri: sourceUri ?? uri);
  }

  bool isAdSignalActiveForRequest(Uri uri, {Uri? sourceUri}) {
    final key = resolveRequestSignalKey(uri, sourceUri: sourceUri);
    return _isSignalActive(_adSignalStates, key);
  }

  bool isPlaybackStalledForRequest(Uri uri, {Uri? sourceUri}) {
    final key = resolveRequestSignalKey(uri, sourceUri: sourceUri);
    return _isSignalActive(_stallSignalStates, key);
  }

  Future<AdblockDecision> evaluateRequest({
    required Uri uri,
    required String resourceType,
    Uri? sourceUri,
    bool fromServiceWorker = false,
    bool? adShowing,
    bool? playbackStalled,
    String? adSignalKey,
  }) {
    final effectiveSignalKey =
        (adSignalKey ?? resolveRequestSignalKey(uri, sourceUri: sourceUri))
            .trim()
            .toLowerCase();
    final effectiveAdShowing =
        adShowing ??
        _isSignalActive(
          _adSignalStates,
          effectiveSignalKey.isEmpty ? _mainFrameSignalKey : effectiveSignalKey,
        );
    final effectivePlaybackStalled =
        playbackStalled ??
        _isSignalActive(
          _stallSignalStates,
          effectiveSignalKey.isEmpty ? _mainFrameSignalKey : effectiveSignalKey,
        );
    final context = AdblockRequestContext(
      uri: uri,
      resourceType: resourceType,
      sourceUrl: sourceUri,
      fromServiceWorker: fromServiceWorker,
      adShowing: effectiveAdShowing,
      playbackStalled: effectivePlaybackStalled,
      adSignalKey: effectiveSignalKey.isEmpty ? null : effectiveSignalKey,
    );
    return _manager.evaluate(context);
  }

  Future<void> syncRuntimeLayers({bool force = false}) async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    final nativeResources = await _manager.getCosmeticResources(
      _currentPageUri,
    );
    final additionalHideSelectors = await _resolveHiddenClassIdSelectors(
      controller,
      nativeResources: nativeResources,
    );
    await _cosmeticFilterInjector.injectIfNeeded(
      controller,
      pageUri: _currentPageUri,
      nativeResources: nativeResources,
      additionalHideSelectors: additionalHideSelectors,
      force: force,
    );
    await _scriptletInjector.injectIfNeeded(
      controller,
      pageUri: _currentPageUri,
      nativeResources: nativeResources,
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
    if (_serviceWorkerAttached &&
        defaultTargetPlatform == TargetPlatform.android) {
      try {
        await ServiceWorkerController.instance().setServiceWorkerClient(null);
      } catch (_) {}
    }
    _serviceWorkerAttached = false;
    _serviceWorkerBlockCount = 0;
    _adSignalStates.clear();
    _stallSignalStates.clear();
    _mainFrameSignalKey = 'global';
  }

  Future<void> _configureServiceWorkerInterception() async {
    if (!_config.serviceWorkerInterceptionEnabled) {
      _logger.log('service worker interception disabled by config');
      return;
    }
    if (_serviceWorkerAttached ||
        defaultTargetPlatform != TargetPlatform.android) {
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
            final redirectDataUrl = (decision.redirectDataUrl ?? '').trim();
            if (redirectDataUrl.isNotEmpty) {
              try {
                final uriData = UriData.fromUri(Uri.parse(redirectDataUrl));
                return WebResourceResponse(
                  contentType: uriData.mimeType.trim().isEmpty
                      ? 'text/plain'
                      : uriData.mimeType.trim(),
                  contentEncoding: uriData.charset.trim().isEmpty
                      ? 'utf-8'
                      : uriData.charset.trim(),
                  data: Uint8List.fromList(uriData.contentAsBytes()),
                  statusCode: 200,
                  reasonPhrase: 'OK',
                  headers: const <String, String>{'Cache-Control': 'no-store'},
                );
              } catch (_) {
                return WebResourceResponse(
                  contentType: 'text/plain',
                  data: Uint8List(0),
                  statusCode: 204,
                  reasonPhrase: 'No Content',
                  headers: const <String, String>{'Cache-Control': 'no-store'},
                );
              }
            }
            final rewrittenUrl = (decision.rewrittenUrl ?? '').trim();
            if (rewrittenUrl.isNotEmpty) {
              return WebResourceResponse(
                contentType: 'text/plain',
                data: Uint8List(0),
                statusCode: 307,
                reasonPhrase: 'Temporary Redirect',
                headers: <String, String>{
                  'Cache-Control': 'no-store',
                  'Location': rewrittenUrl,
                },
              );
            }
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

  Future<Set<String>> _resolveHiddenClassIdSelectors(
    InAppWebViewController controller, {
    required AdblockCosmeticResources? nativeResources,
  }) async {
    final pageUri = _currentPageUri;
    if (pageUri == null || pageUri.host.isEmpty) {
      return const <String>{};
    }
    if (nativeResources?.generichide == true) {
      return const <String>{};
    }

    final domSignals = await _collectDomClassIdSignals(controller);
    if (domSignals.isEmpty) {
      return const <String>{};
    }

    final selectors = await _manager.getHiddenClassIdSelectors(
      pageUri,
      classes: domSignals.classes,
      ids: domSignals.ids,
      exceptions: nativeResources?.exceptions ?? const <String>{},
    );
    return selectors
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toSet();
  }

  Future<_DomClassIdSignals> _collectDomClassIdSignals(
    InAppWebViewController controller,
  ) async {
    const script = '''
(function() {
  try {
    var maxSignals = 480;
    var classes = new Set();
    var ids = new Set();
    var nodes = document.querySelectorAll('[class],[id]');
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i];
      if (node && node.id) {
        ids.add(String(node.id));
      }
      if (node && node.classList) {
        for (var j = 0; j < node.classList.length; j++) {
          var cls = node.classList[j];
          if (cls) {
            classes.add(String(cls));
          }
          if (classes.size >= maxSignals) {
            break;
          }
        }
      }
      if (classes.size >= maxSignals && ids.size >= maxSignals) {
        break;
      }
    }
    return JSON.stringify({
      classes: Array.from(classes).slice(0, maxSignals),
      ids: Array.from(ids).slice(0, maxSignals)
    });
  } catch (_) {
    return JSON.stringify({ classes: [], ids: [] });
  }
})();
''';
    try {
      final payload = await controller.evaluateJavascript(source: script);
      final decoded = _decodeJsonPayload(payload);
      if (decoded == null) {
        return const _DomClassIdSignals(classes: <String>[], ids: <String>[]);
      }
      List<String> asList(String key) {
        final raw = decoded[key];
        if (raw is List<dynamic>) {
          return raw
              .map((entry) => entry.toString().trim())
              .where((entry) => entry.isNotEmpty)
              .take(_maxCosmeticDomSignals)
              .toList(growable: false);
        }
        return const <String>[];
      }

      return _DomClassIdSignals(classes: asList('classes'), ids: asList('ids'));
    } catch (_) {
      return const _DomClassIdSignals(classes: <String>[], ids: <String>[]);
    }
  }

  String _requestSignalKeyFor({Uri? uri, String? fallbackVideoId}) {
    final directVideoId = (fallbackVideoId ?? '').trim();
    if (directVideoId.isNotEmpty) {
      return 'video:${directVideoId.toLowerCase()}';
    }
    if (uri == null) {
      return _mainFrameSignalKey;
    }
    final videoId = _videoIdFromUri(uri);
    if (videoId.isNotEmpty) {
      return 'video:${videoId.toLowerCase()}';
    }
    final host = uri.host.trim().toLowerCase();
    if (host.isEmpty) {
      return _mainFrameSignalKey;
    }
    final path = uri.path.trim().toLowerCase();
    if (path.startsWith('/watch') && _mainFrameSignalKey != 'global') {
      return _mainFrameSignalKey;
    }
    if (path.isNotEmpty && path != '/') {
      return 'source:$host$path';
    }
    return 'host:$host';
  }

  String _videoIdFromUri(Uri uri) {
    final queryVideoId = (uri.queryParameters['v'] ?? '').trim();
    if (queryVideoId.isNotEmpty) {
      return queryVideoId;
    }
    final segments = uri.pathSegments;
    final shortsIndex = segments.indexOf('shorts');
    if (shortsIndex >= 0 && segments.length > shortsIndex + 1) {
      return segments[shortsIndex + 1].trim();
    }
    return '';
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  void _setSignal(
    LinkedHashMap<String, DateTime> map,
    String key, {
    required Duration ttl,
  }) {
    final normalizedKey = key.trim().toLowerCase();
    if (normalizedKey.isEmpty) {
      return;
    }
    _pruneExpiredSignals(map);
    map.remove(normalizedKey);
    map[normalizedKey] = DateTime.now().add(ttl);
    _trimSignalMap(map);
  }

  bool _isSignalActive(LinkedHashMap<String, DateTime> map, String key) {
    final normalizedKey = key.trim().toLowerCase();
    if (normalizedKey.isEmpty) {
      return false;
    }
    _pruneExpiredSignals(map);
    final expiresAt = map.remove(normalizedKey);
    if (expiresAt == null) {
      return false;
    }
    if (DateTime.now().isAfter(expiresAt)) {
      return false;
    }
    map[normalizedKey] = expiresAt;
    return true;
  }

  void _pruneExpiredSignals(LinkedHashMap<String, DateTime> map) {
    if (map.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final expiredKeys = <String>[];
    for (final entry in map.entries) {
      if (now.isAfter(entry.value)) {
        expiredKeys.add(entry.key);
      }
    }
    for (final key in expiredKeys) {
      map.remove(key);
    }
  }

  void _trimSignalMap(LinkedHashMap<String, DateTime> map) {
    while (map.length > _maxSignalStateEntries) {
      map.remove(map.keys.first);
    }
  }

  Map<String, dynamic>? _decodeJsonPayload(dynamic payload) {
    if (payload is Map<String, dynamic>) {
      return payload;
    }
    if (payload is Map) {
      return payload.map((key, value) => MapEntry(key.toString(), value));
    }
    if (payload is! String) {
      return null;
    }
    final trimmed = payload.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      final firstDecode = jsonDecode(trimmed);
      if (firstDecode is Map<String, dynamic>) {
        return firstDecode;
      }
      if (firstDecode is Map) {
        return firstDecode.map((key, value) => MapEntry(key.toString(), value));
      }
      if (firstDecode is String) {
        final secondDecode = jsonDecode(firstDecode);
        if (secondDecode is Map<String, dynamic>) {
          return secondDecode;
        }
        if (secondDecode is Map) {
          return secondDecode.map(
            (key, value) => MapEntry(key.toString(), value),
          );
        }
      }
    } catch (_) {
      return null;
    }
    return null;
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
        (headers['Sec-Fetch-Dest'] ?? headers['sec-fetch-dest'] ?? '')
            .toLowerCase();
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

class _DomClassIdSignals {
  const _DomClassIdSignals({required this.classes, required this.ids});

  final List<String> classes;
  final List<String> ids;

  bool get isEmpty => classes.isEmpty && ids.isEmpty;
}
