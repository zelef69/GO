import 'dart:convert';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'adblock_config.dart';
import 'adblock_debug_logger.dart';
import 'adblock_manager.dart';
import 'cosmetic_filter_injector.dart';
import 'request_blocker.dart';
import 'scriptlet_injector.dart';
import '../intercept/request_interceptor.dart';
import 'types.dart';

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
  final RequestInterceptor _requestInterceptor = const RequestInterceptor();

  AdblockConfig _config;
  InAppWebViewController? _controller;
  Uri? _currentPageUri;
  bool _serviceWorkerAttached = false;
  int _serviceWorkerBlockCount = 0;
  final LinkedHashMap<String, DateTime> _adSignalStates =
      LinkedHashMap<String, DateTime>();
  final LinkedHashMap<String, DateTime> _stallSignalStates =
      LinkedHashMap<String, DateTime>();
  final LinkedHashMap<String, int> _stallPulseCounts =
      LinkedHashMap<String, int>();
  String _mainFrameSignalKey = 'global';
  static const int _maxServiceWorkerBlockLogs = 80;
  static const int _maxCosmeticDomSignals = 480;
  static const Duration _adSignalTtl = Duration(milliseconds: 2400);
  static const Duration _jsAdSignalTtl = Duration(milliseconds: 5600);
  static const Duration _jsAntiAdblockSignalTtl = Duration(milliseconds: 9000);
  static const Duration _stallSignalTtl = Duration(milliseconds: 4200);
  static const int _adSignalStallPulseResetThreshold = 4;
  static const int _maxSignalStateEntries = 420;
  static const Duration _interceptProbeWindow = Duration(seconds: 10);
  static const int _maxInterceptProbeLogs = 120;
  static const int _maxHookLifecycleLogs = 80;
  static const int _maxSignalDebugLogs = 260;
  static const int _maxRequestFlowLogs = 320;
  int _hookLifecycleLogCount = 0;
  int _signalDebugLogCount = 0;
  int _requestFlowLogCount = 0;
  int _interceptProbeWindowStartMs = 0;
  int _interceptProbeLogCount = 0;
  int _interceptProbeRequestCount = 0;
  int _interceptProbeBlockedCount = 0;
  int _interceptProbeServiceWorkerCount = 0;
  int _interceptProbeAdSignalCount = 0;
  int _interceptProbeStallCount = 0;
  final Map<String, int> _interceptProbeTypeCounts = <String, int>{};
  final Map<String, int> _interceptProbeReasonCounts = <String, int>{};

  Uri? get currentPageUri => _currentPageUri;

  Map<String, dynamic> get debugSnapshot => <String, dynamic>{
    'page': _pageSummary(_currentPageUri),
    'mainFrameSignalKey': _mainFrameSignalKey,
    'serviceWorkerAttached': _serviceWorkerAttached,
    'serviceWorkerBlockCount': _serviceWorkerBlockCount,
    'adSignalEntries': _adSignalStates.length,
    'stallSignalEntries': _stallSignalStates.length,
    'stallPulseEntries': _stallPulseCounts.length,
    'interceptProbe': <String, dynamic>{
      'windowStartMs': _interceptProbeWindowStartMs,
      'requests': _interceptProbeRequestCount,
      'blocked': _interceptProbeBlockedCount,
      'serviceWorker': _interceptProbeServiceWorkerCount,
      'adSignal': _interceptProbeAdSignalCount,
      'stalled': _interceptProbeStallCount,
      'typeCounts': Map<String, int>.from(_interceptProbeTypeCounts),
      'reasonCounts': Map<String, int>.from(_interceptProbeReasonCounts),
    },
  };

  void updateConfig(AdblockConfig config) {
    _config = config;
    _cosmeticFilterInjector.setConfig(config);
    _scriptletInjector.setConfig(config);
  }

  Future<void> attachWebView(InAppWebViewController controller) async {
    final replacingController =
        _controller != null && !identical(_controller, controller);
    _controller = controller;
    _logHookLifecycle(
      'hook attach replacing=$replacingController swAttached=$_serviceWorkerAttached',
    );
    await ensureInterceptionAttached(reason: 'attach_webview');
  }

  Future<void> ensureInterceptionAttached({required String reason}) async {
    if (_controller == null) {
      _logHookLifecycle('hook ensure reason=$reason controller=missing');
      return;
    }
    if (!_config.enabled) {
      _logHookLifecycle('hook ensure reason=$reason adblock=disabled');
      return;
    }
    final before = _serviceWorkerAttached;
    await _configureServiceWorkerInterception();
    _logHookLifecycle(
      'hook ensure reason=$reason swBefore=$before swAfter=$_serviceWorkerAttached page=${_pageSummary(_currentPageUri)}',
    );
  }

  void onMainFrameChanged(Uri? uri) {
    final previousSignalKey = _mainFrameSignalKey;
    final nextSignalKey = _requestSignalKeyFor(uri: uri);
    final previousPage = _pageSummary(_currentPageUri);
    final nextPage = _pageSummary(uri);
    if (previousSignalKey != nextSignalKey || previousPage != nextPage) {
      clearSignalState(
        reason: previousSignalKey != nextSignalKey
            ? 'main_frame_changed'
            : 'main_frame_navigated',
      );
    }
    _mainFrameSignalKey = nextSignalKey;
    _currentPageUri = uri;
    _manager.onMainFrameChanged(uri);
    _logSignalDebug(
      'อัปเดต main frame page=${_pageSummary(uri)} keyเดิม=$previousSignalKey keyใหม่=$nextSignalKey',
    );
  }

  void clearSignalState({String reason = 'manual'}) {
    if (_adSignalStates.isEmpty &&
        _stallSignalStates.isEmpty &&
        _stallPulseCounts.isEmpty) {
      return;
    }
    _adSignalStates.clear();
    _stallSignalStates.clear();
    _stallPulseCounts.clear();
    _logger.log('ล้างสถานะสัญญาณ ad/stall แล้ว reason=$reason');
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
    final hasExplicitAdSignal = adShowing || adInterrupting || hasAdOverlay;
    if (hasExplicitAdSignal) {
      _setSignal(_adSignalStates, signalKey, ttl: _adSignalTtl);
      _stallPulseCounts.remove(signalKey);
    }

    final eventName = (payload['event'] ?? '').toString().trim().toLowerCase();
    final readyState = _toInt(payload['readyState']);
    final networkState = _toInt(payload['networkState']);
    final currentTimeMs = _toInt(payload['currentTimeMs']);
    final bufferedAheadMs = _toInt(payload['bufferedAheadMs']);
    final paused = payload['paused'] == true;
    final ended = payload['ended'] == true;
    final spinnerVisible = payload['spinnerVisible'] == true;
    final stallLikeEvent =
        eventName == 'video:waiting' ||
        eventName == 'video:stalled' ||
        eventName == 'video:emptied' ||
        eventName == 'video:loadstart' ||
        eventName == 'video:suspend';
    final waitingNetworkState =
        networkState == 0 || networkState == 2 || networkState == 3;
    final bufferEmpty = bufferedAheadMs <= 120;
    final playbackShouldAdvance = !paused && !ended && currentTimeMs > 0;
    final runtimeStallSnapshot =
        playbackShouldAdvance &&
        bufferEmpty &&
        readyState <= 2 &&
        (waitingNetworkState || spinnerVisible);
    final looksStalled =
        (stallLikeEvent &&
            waitingNetworkState &&
            (readyState <= 2 || bufferEmpty)) ||
        runtimeStallSnapshot;
    final recoveredByBuffer = readyState >= 2 && bufferedAheadMs >= 900;
    final recoveredByReadyState =
        readyState >= 3 && !bufferEmpty && !spinnerVisible;
    final recovered =
        eventName == 'video:playing' ||
        eventName == 'video:canplay' ||
        eventName == 'video:canplaythrough' ||
        ended ||
        recoveredByBuffer ||
        recoveredByReadyState;

    if (looksStalled) {
      _setSignal(_stallSignalStates, signalKey, ttl: _stallSignalTtl);
      final nextStallPulse = (_stallPulseCounts[signalKey] ?? 0) + 1;
      _stallPulseCounts[signalKey] = nextStallPulse;
      _trimStallPulseCounts();
      if (!hasExplicitAdSignal &&
          nextStallPulse >= _adSignalStallPulseResetThreshold) {
        final removedAdSignal = _adSignalStates.remove(signalKey) != null;
        if (removedAdSignal) {
          _logSignalDebug(
            'stall fail-safe -> clear ad signal key=$signalKey pulses=$nextStallPulse event=$eventName',
          );
        }
        _stallPulseCounts[signalKey] = 0;
      }
      _logSignalDebug(
        'รับ playback debug -> ตีความว่า stall key=$signalKey event=$eventName ready=$readyState net=$networkState bufferMs=$bufferedAheadMs spinner=$spinnerVisible',
      );
    } else if (recovered) {
      _stallSignalStates.remove(signalKey);
      _stallPulseCounts.remove(signalKey);
      _logSignalDebug(
        'รับ playback debug -> ตีความว่าฟื้นตัว key=$signalKey event=$eventName ready=$readyState bufferMs=$bufferedAheadMs',
      );
    }

    _manager.onPlaybackDebugSignal(
      payload,
      pageUri: pageUri ?? _currentPageUri,
    );
  }

  void updateAdblockDebugSignal(Map<String, dynamic> payload, {Uri? pageUri}) {
    final signalKey = _requestSignalKeyFor(
      uri: pageUri ?? _currentPageUri,
      fallbackVideoId: payload['videoId']?.toString().trim(),
    );
    if (signalKey == 'global') {
      return;
    }
    final eventName = (payload['event'] ?? '').toString().trim().toLowerCase();
    final reason = (payload['reason'] ?? '').toString().trim().toLowerCase();
    final blocked = payload['blocked'] == true;
    final resourceType = (payload['resourceType'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    final antiAdblockEvent =
        eventName.startsWith('anti_adblock') || reason.contains('anti_adblock');
    final networkAdMatch = eventName == 'network_ad_match' && blocked;
    final googlevideoSignal =
        resourceType == 'media' && reason.contains('googlevideo_ad_query');

    if (antiAdblockEvent) {
      _setSignal(_adSignalStates, signalKey, ttl: _jsAntiAdblockSignalTtl);
      _setSignal(_stallSignalStates, signalKey, ttl: _stallSignalTtl);
      _logSignalDebug(
        'รับ adblock debug -> พบสัญญาณ anti-adblock key=$signalKey event=$eventName reason=$reason จึงเร่ง ad/stall signal',
      );
      return;
    }

    if (networkAdMatch || googlevideoSignal) {
      _setSignal(_adSignalStates, signalKey, ttl: _jsAdSignalTtl);
      if (resourceType == 'media') {
        _setSignal(_stallSignalStates, signalKey, ttl: _stallSignalTtl);
      }
      _logSignalDebug(
        'รับ adblock debug -> พบ network ad match key=$signalKey event=$eventName reason=$reason type=$resourceType blocked=$blocked',
      );
    }
  }

  String resolveRequestSignalKey(Uri uri, {Uri? sourceUri}) {
    final resolved = _requestSignalKeyFor(uri: sourceUri ?? uri);
    return _promoteSignalKeyForRequest(
      requestUri: uri,
      sourceUri: sourceUri,
      resolvedKey: resolved,
    );
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
  }) async {
    final startedAtMs = DateTime.now().millisecondsSinceEpoch;
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
    final decision = await _manager.evaluate(context);
    _recordInterceptProbe(context, decision);
    _logRequestFlow(
      'ประเมินคำขอผ่าน WebView host=${uri.host} path=${uri.path} type=${resourceType.toLowerCase()} blocked=${decision.blocked} reason=${decision.reason} cache=${decision.fromCache} sw=$fromServiceWorker adShowing=$effectiveAdShowing stalled=$effectivePlaybackStalled key=${effectiveSignalKey.isEmpty ? _mainFrameSignalKey : effectiveSignalKey} page=${_pageSummary(sourceUri ?? _currentPageUri)} ใช้เวลาMs=${DateTime.now().millisecondsSinceEpoch - startedAtMs}',
    );
    return decision;
  }

  Future<void> syncRuntimeLayers({bool force = false}) async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    final cosmeticPayload = await _manager.getCosmeticPayload(_currentPageUri);
    final scriptletPayload = await _manager.getScriptletPayload(
      _currentPageUri,
    );
    final additionalHideSelectors = await _resolveHiddenClassIdSelectors(
      controller,
      cosmeticPayload: cosmeticPayload,
    );
    await _cosmeticFilterInjector.injectIfNeeded(
      controller,
      pageUri: _currentPageUri,
      payload: cosmeticPayload,
      additionalHideSelectors: additionalHideSelectors,
      force: force,
    );
    await _scriptletInjector.injectIfNeeded(
      controller,
      pageUri: _currentPageUri,
      payload: scriptletPayload,
      force: force,
    );
  }

  Future<void> onPageStarted(Uri? uri) async {
    await ensureInterceptionAttached(reason: 'page_started');
    onMainFrameChanged(uri);
    await syncRuntimeLayers();
  }

  Future<void> onPageFinished(Uri? uri) async {
    await ensureInterceptionAttached(reason: 'page_finished');
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
    _stallPulseCounts.clear();
    _mainFrameSignalKey = 'global';
    _hookLifecycleLogCount = 0;
    _interceptProbeWindowStartMs = 0;
    _interceptProbeLogCount = 0;
    _interceptProbeRequestCount = 0;
    _interceptProbeBlockedCount = 0;
    _interceptProbeServiceWorkerCount = 0;
    _interceptProbeAdSignalCount = 0;
    _interceptProbeStallCount = 0;
    _interceptProbeTypeCounts.clear();
    _interceptProbeReasonCounts.clear();
  }

  Future<void> _configureServiceWorkerInterception() async {
    if (!_config.serviceWorkerInterceptionEnabled) {
      _logger.log('ปิดการดักจับ service worker ตาม config');
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
      _logger.log('อุปกรณ์นี้ไม่รองรับ service worker interception');
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
                'service worker บล็อกคำขอ host=${uri.host} path=${uri.path} reason=${decision.reason}',
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
      _logger.log('เปิดใช้งาน service worker interception สำเร็จ');
    } catch (_) {
      _logger.log('ตั้งค่า service worker interception ไม่สำเร็จ');
    }
  }

  Future<Set<String>> _resolveHiddenClassIdSelectors(
    InAppWebViewController controller, {
    required CosmeticPayload cosmeticPayload,
  }) async {
    final pageUri = _currentPageUri;
    if (pageUri == null || pageUri.host.isEmpty) {
      return const <String>{};
    }
    if (cosmeticPayload.generichide) {
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
      exceptions: cosmeticPayload.exceptions,
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

  String _promoteSignalKeyForRequest({
    required Uri requestUri,
    required Uri? sourceUri,
    required String resolvedKey,
  }) {
    final normalizedMainKey = _mainFrameSignalKey.trim().toLowerCase();
    if (!normalizedMainKey.startsWith('video:')) {
      return resolvedKey;
    }
    final requestHost = requestUri.host.trim().toLowerCase();
    final effectiveSource = sourceUri ?? _currentPageUri;
    final sourceHost = effectiveSource?.host.trim().toLowerCase() ?? '';
    final sourcePath = effectiveSource?.path.trim().toLowerCase() ?? '';

    if (_isGoogleVideoHost(requestHost) && _isYouTubeHost(sourceHost)) {
      if (_isGenericYouTubeSourcePath(sourcePath) ||
          _videoIdFromUri(effectiveSource!) != '') {
        return normalizedMainKey;
      }
    }

    if (_isYouTubeHost(requestHost) &&
        _isGenericYouTubeSourcePath(sourcePath)) {
      return normalizedMainKey;
    }
    return resolvedKey;
  }

  bool _isYouTubeHost(String host) {
    return host == 'youtube.com' || host.endsWith('.youtube.com');
  }

  bool _isGoogleVideoHost(String host) {
    return host == 'googlevideo.com' || host.endsWith('.googlevideo.com');
  }

  bool _isGenericYouTubeSourcePath(String path) {
    if (path.isEmpty || path == '/') {
      return true;
    }
    if (path == '/watch' || path.startsWith('/watch')) {
      return true;
    }
    return false;
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

  void _trimStallPulseCounts() {
    while (_stallPulseCounts.length > _maxSignalStateEntries) {
      _stallPulseCounts.remove(_stallPulseCounts.keys.first);
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
    return _requestInterceptor.sourceUriFromHeaders(headers);
  }

  String _resourceTypeFromRequest(WebResourceRequest request) {
    final requestUri = Uri.tryParse(request.url.toString());
    if (requestUri == null) {
      return 'other';
    }
    return _requestInterceptor.classifyResourceType(
      url: requestUri,
      isMainFrame: request.isForMainFrame == true,
      headers: request.headers,
    );
  }

  void _recordInterceptProbe(
    AdblockRequestContext request,
    AdblockDecision decision,
  ) {
    if (!_config.debugMode) {
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_interceptProbeWindowStartMs <= 0) {
      _interceptProbeWindowStartMs = nowMs;
    }
    if (nowMs - _interceptProbeWindowStartMs >=
        _interceptProbeWindow.inMilliseconds) {
      _flushInterceptProbe(nowMs);
    }
    _interceptProbeRequestCount += 1;
    if (decision.blocked) {
      _interceptProbeBlockedCount += 1;
    }
    if (request.fromServiceWorker) {
      _interceptProbeServiceWorkerCount += 1;
    }
    if (request.adShowing) {
      _interceptProbeAdSignalCount += 1;
    }
    if (request.playbackStalled) {
      _interceptProbeStallCount += 1;
    }
    final typeKey = request.resourceType.trim().toLowerCase();
    if (typeKey.isNotEmpty) {
      _interceptProbeTypeCounts.update(
        typeKey,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    final reasonKey = '${decision.blocked ? 'b' : 'a'}:${decision.reason}';
    _interceptProbeReasonCounts.update(
      reasonKey,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
  }

  void _flushInterceptProbe(int nowMs) {
    if (_interceptProbeRequestCount > 0 &&
        _interceptProbeLogCount < _maxInterceptProbeLogs) {
      _interceptProbeLogCount += 1;
      _logger.log(
        'สรุปการดักจับคำขอ 10วินาที req=$_interceptProbeRequestCount blocked=$_interceptProbeBlockedCount sw=$_interceptProbeServiceWorkerCount adSignal=$_interceptProbeAdSignalCount stalled=$_interceptProbeStallCount page=${_pageSummary(_currentPageUri)} mainKey=$_mainFrameSignalKey topType=${_topSummary(_interceptProbeTypeCounts, limit: 4)} topReason=${_topSummary(_interceptProbeReasonCounts, limit: 4)}',
      );
    }
    _interceptProbeWindowStartMs = nowMs;
    _interceptProbeRequestCount = 0;
    _interceptProbeBlockedCount = 0;
    _interceptProbeServiceWorkerCount = 0;
    _interceptProbeAdSignalCount = 0;
    _interceptProbeStallCount = 0;
    _interceptProbeTypeCounts.clear();
    _interceptProbeReasonCounts.clear();
  }

  void _logHookLifecycle(String message) {
    if (!_config.debugMode || _hookLifecycleLogCount >= _maxHookLifecycleLogs) {
      return;
    }
    _hookLifecycleLogCount += 1;
    _logger.log(message);
  }

  void _logSignalDebug(String message) {
    if (!_config.debugMode || _signalDebugLogCount >= _maxSignalDebugLogs) {
      return;
    }
    _signalDebugLogCount += 1;
    _logger.log('signal_debug $message');
  }

  void _logRequestFlow(String message) {
    if (!_config.debugMode || _requestFlowLogCount >= _maxRequestFlowLogs) {
      return;
    }
    _requestFlowLogCount += 1;
    _logger.log('request_flow $message');
  }

  String _pageSummary(Uri? uri) {
    if (uri == null) {
      return 'none';
    }
    final host = uri.host.trim().toLowerCase();
    final path = uri.path.trim().isEmpty ? '/' : uri.path.trim();
    if (host.isEmpty) {
      return path;
    }
    return '$host$path';
  }

  String _topSummary(Map<String, int> counts, {required int limit}) {
    if (counts.isEmpty) {
      return 'none';
    }
    final entries = counts.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    return entries
        .take(limit)
        .map((entry) => '${entry.key}:${entry.value}')
        .join(',');
  }
}

class _DomClassIdSignals {
  const _DomClassIdSignals({required this.classes, required this.ids});

  final List<String> classes;
  final List<String> ids;

  bool get isEmpty => classes.isEmpty && ids.isEmpty;
}
