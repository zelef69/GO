import 'package:flutter/foundation.dart';

import 'adblock_engine_bridge.dart';
import 'filter_list_loader.dart';
import 'models/adblock_rule.dart';
import 'youtube_ad_request_matcher.dart';

class AdblockService {
  static const List<String> _googleVideoAdQueryHints = <String>[
    'oad',
    'adformat',
    'ad_type',
    'ad_preroll',
    'dclk_video_ads',
    'ad3_module',
    'videoadid',
    'adtag',
    'ad_tag',
    'ad_debug',
    'adsid',
    'ad_host_tier',
    'ad_flags',
  ];

  AdblockService({
    required FilterListLoader filterListLoader,
    required AdblockEngineBridge nativeEngineBridge,
    required AdblockEngineBridge fallbackEngineBridge,
    required bool enabled,
  }) : _filterListLoader = filterListLoader,
       _nativeEngineBridge = nativeEngineBridge,
       _fallbackEngineBridge = fallbackEngineBridge,
       _enabled = enabled;

  final FilterListLoader _filterListLoader;
  final AdblockEngineBridge _nativeEngineBridge;
  final AdblockEngineBridge _fallbackEngineBridge;

  bool _enabled;
  bool _initialized = false;
  late AdblockEngineBridge _activeEngine;
  List<AdblockRule> _rules = const <AdblockRule>[];
  bool _fallbackInitialized = false;
  int _debugBlockLogCount = 0;

  bool get enabled => _enabled;
  bool _usingNativeEngine = false;
  bool get usingNativeEngine => _usingNativeEngine;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _rules = await _filterListLoader.load();
    await _fallbackEngineBridge.initialize(_rules);
    _fallbackInitialized = true;

    final isNativeAvailable = await _nativeEngineBridge.isAvailable();

    if (isNativeAvailable) {
      try {
        await _nativeEngineBridge.initialize(_rules);
        _activeEngine = _nativeEngineBridge;
        _usingNativeEngine = true;
        _initialized = true;
        _log('Initialized native engine with ${_rules.length} rules');
        return;
      } catch (_) {
        _usingNativeEngine = false;
        _log('Native engine init failed, switching to fallback');
      }
    }

    _activeEngine = _fallbackEngineBridge;
    _initialized = true;
    _log('Initialized fallback engine with ${_rules.length} rules');
  }

  void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  Future<bool> shouldBlockRequest(
    Uri? uri, {
    required String resourceType,
    Uri? sourceUrl,
  }) async {
    if (!_enabled || uri == null) {
      return false;
    }

    // Fast-path most media chunks before matcher/engine work.
    // Keep ad-like query hints in the slow path for correctness.
    if (_isPrimaryPlaybackMediaRequest(uri, resourceType: resourceType) &&
        !_hasGoogleVideoAdQueryHint(uri)) {
      return false;
    }

    // Keep a conservative heuristic layer even when native engine is active.
    // Keep this available even before async engine init completes.
    final blockedByMatcher = YouTubeAdRequestMatcher.matches(uri);
    if (blockedByMatcher) {
      _logBlocked('matcher', uri);
      return true;
    }

    if (!_initialized) {
      return false;
    }

    final blockedByActive = await _safeShouldBlock(
      _activeEngine,
      uri,
      resourceType: resourceType,
      sourceUrl: sourceUrl,
    );
    if (blockedByActive) {
      _logBlocked(
        _usingNativeEngine ? 'native-engine' : 'fallback-engine',
        uri,
      );
      return true;
    }

    return false;
  }

  bool _isPrimaryPlaybackMediaRequest(Uri uri, {required String resourceType}) {
    final normalizedType = resourceType.toLowerCase();
    if (normalizedType == 'document' || normalizedType == 'subdocument') {
      return false;
    }

    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    final isGoogleVideoHost =
        host == 'googlevideo.com' || host.endsWith('.googlevideo.com');
    if (!isGoogleVideoHost) {
      return false;
    }
    if (!path.contains('/videoplayback')) {
      return false;
    }
    return normalizedType == 'media' ||
        normalizedType == 'xmlhttprequest' ||
        normalizedType == 'other';
  }

  bool _hasGoogleVideoAdQueryHint(Uri uri) {
    final query = uri.query.toLowerCase();
    if (query.isEmpty) {
      return false;
    }
    final normalizedQuery = '&$query&';
    for (final key in _googleVideoAdQueryHints) {
      if (normalizedQuery.contains('&$key=') ||
          normalizedQuery.contains('&$key&')) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _safeShouldBlock(
    AdblockEngineBridge engine,
    Uri uri, {
    required String resourceType,
    Uri? sourceUrl,
  }) async {
    try {
      return await engine.shouldBlock(
        uri,
        resourceType: resourceType,
        sourceUrl: sourceUrl,
      );
    } catch (_) {
      _log('Engine shouldBlock failed for ${uri.host}${uri.path}');
      return false;
    }
  }

  Future<void> _safeDispose(AdblockEngineBridge engine) async {
    try {
      await engine.dispose();
    } catch (_) {}
  }

  void _log(String message) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('[GO_PLAY-Adblock] $message');
  }

  void _logBlocked(String source, Uri uri) {
    if (!kDebugMode || _debugBlockLogCount >= 40) {
      return;
    }
    _debugBlockLogCount += 1;
    debugPrint('[GO_PLAY-Adblock] Blocked by $source -> ${uri.host}${uri.path}');
  }

  Future<void> dispose() async {
    if (!_initialized) {
      return;
    }

    if (_usingNativeEngine) {
      await _safeDispose(_nativeEngineBridge);
    }
    if (_fallbackInitialized) {
      await _safeDispose(_fallbackEngineBridge);
    }

    _initialized = false;
    _fallbackInitialized = false;
    _usingNativeEngine = false;
    _rules = const <AdblockRule>[];
    _activeEngine = _fallbackEngineBridge;
    _debugBlockLogCount = 0;
  }
}
