import 'dart:collection';

import '../../domain_lock/domain_policy_service.dart';
import '../adblock_engine_bridge.dart';
import '../youtube_ad_request_matcher.dart';
import 'adblock_config.dart';
import 'adblock_debug_logger.dart';
import 'adblock_metrics.dart';

class AdblockRequestContext {
  const AdblockRequestContext({
    required this.uri,
    required this.resourceType,
    required this.sourceUrl,
    required this.fromServiceWorker,
  });

  final Uri uri;
  final String resourceType;
  final Uri? sourceUrl;
  final bool fromServiceWorker;
}

class AdblockDecision {
  const AdblockDecision({
    required this.blocked,
    required this.reason,
    this.matchedRule,
    this.fromCache = false,
  });

  final bool blocked;
  final String reason;
  final String? matchedRule;
  final bool fromCache;
}

class RequestBlocker {
  RequestBlocker({
    required DomainPolicyService domainPolicyService,
    required AdblockDebugLogger logger,
    required AdblockMetricsCollector metrics,
  }) : _domainPolicyService = domainPolicyService,
       _logger = logger,
       _metrics = metrics;

  static const int _decisionCacheLimit = 2048;
  static const Duration _decisionCacheTtl = Duration(seconds: 25);
  static const List<String> _googleVideoAdQueryKeys = <String>[
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
    'ad_cpn',
    'adid',
    'ad_url',
    'adurl',
    'ad_slot',
    'adslot',
    'adslotname',
    'adcontext',
    'adcontexturl',
    'ad_break',
  ];

  final DomainPolicyService _domainPolicyService;
  final AdblockDebugLogger _logger;
  final AdblockMetricsCollector _metrics;
  final LinkedHashMap<String, _DecisionCacheEntry> _decisionCache =
      LinkedHashMap<String, _DecisionCacheEntry>();
  AdblockConfig _config = AdblockConfig.defaults(
    enabled: true,
    debugMode: false,
  );
  AdblockEngineBridge? _engine;

  void setConfig(AdblockConfig config) {
    _config = config;
    _decisionCache.clear();
  }

  void setEngine(AdblockEngineBridge engine) {
    _engine = engine;
  }

  void clearCache() {
    _decisionCache.clear();
  }

  Future<AdblockDecision> evaluate(AdblockRequestContext request) async {
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    final result = await _evaluateInternal(request);
    final elapsedMs = DateTime.now().millisecondsSinceEpoch - startedAt;
    _metrics.onDecision(
      blocked: result.blocked,
      elapsedMs: elapsedMs,
      matchedRule: result.matchedRule,
      reason: result.reason,
    );
    return result;
  }

  Future<AdblockDecision> _evaluateInternal(
    AdblockRequestContext request,
  ) async {
    final uri = request.uri;
    final normalizedType = request.resourceType.toLowerCase();

    if (!_config.enabled) {
      return const AdblockDecision(blocked: false, reason: 'disabled');
    }

    if (_isAllowlisted(uri.host)) {
      return const AdblockDecision(blocked: false, reason: 'allowlisted_host');
    }

    if (_isBlocklisted(uri.host)) {
      return AdblockDecision(
        blocked: true,
        reason: 'blocklisted_host',
        matchedRule: uri.host,
      );
    }

    if (!_domainPolicyService.isRequestAllowed(uri)) {
      return AdblockDecision(
        blocked: true,
        reason: 'domain_policy',
        matchedRule: uri.host,
      );
    }

    if (normalizedType == 'document' || normalizedType == 'subdocument') {
      return const AdblockDecision(
        blocked: false,
        reason: 'document_pass_through',
      );
    }

    if (uri.scheme.toLowerCase() != 'https') {
      return const AdblockDecision(blocked: false, reason: 'non_https');
    }

    if (_isSkippableStaticResource(uri, normalizedType)) {
      return const AdblockDecision(blocked: false, reason: 'static_fast_path');
    }

    // Keep high-churn first-party telemetry fail-open to prevent retry storms
    // that can trap YouTube in long ad-transition black screens.
    if (_isYouTubeTelemetryFastPath(uri, normalizedType)) {
      return const AdblockDecision(
        blocked: false,
        reason: 'youtube_telemetry_fast_path',
      );
    }

    // Block only ad-marked googlevideo playback requests.
    // This keeps normal media streams fail-open while cutting ad streams
    // early to reduce visible ad stall time.
    if (_isGoogleVideoAdPlaybackRequest(uri)) {
      return AdblockDecision(
        blocked: true,
        reason: 'googlevideo_ad_query',
        matchedRule: uri.toString(),
      );
    }

    // Always allow primary googlevideo playback streams to avoid player
    // deadlocks/black-screen stalls while YouTube switches from ad stream
    // to content stream.
    if (_isPrimaryPlaybackMediaRequest(uri, normalizedType)) {
      return const AdblockDecision(blocked: false, reason: 'media_fast_path');
    }

    final decisionCacheKey = _cacheKey(request);
    final cached = _readCache(decisionCacheKey);
    if (cached != null) {
      return cached;
    }

    if (YouTubeAdRequestMatcher.matches(uri)) {
      final decision = AdblockDecision(
        blocked: true,
        reason: 'heuristic_matcher',
        matchedRule: uri.toString(),
      );
      _writeCache(decisionCacheKey, decision);
      return decision;
    }

    final thirdParty = _isThirdPartyRequest(
      requestHost: uri.host,
      sourceHost: request.sourceUrl?.host,
    );
    if (thirdParty &&
        (uri.host.endsWith('.doubleclick.net') ||
            uri.host.endsWith('.googlesyndication.com'))) {
      final decision = AdblockDecision(
        blocked: true,
        reason: 'third_party_tracker',
        matchedRule: uri.host,
      );
      _writeCache(decisionCacheKey, decision);
      return decision;
    }

    // Keep first-party YouTube core traffic fail-open for stability.
    // Ad requests are still blocked by heuristic/third-party checks above.
    if (!thirdParty && _isCoreYouTubeHost(uri.host)) {
      final decision = const AdblockDecision(
        blocked: false,
        reason: 'first_party_core_allow',
      );
      _writeCache(decisionCacheKey, decision);
      return decision;
    }

    final engine = _engine;
    if (engine == null) {
      return const AdblockDecision(blocked: false, reason: 'engine_not_ready');
    }

    bool blockedByEngine = false;
    try {
      blockedByEngine = await engine.shouldBlock(
        uri,
        resourceType: request.resourceType,
        sourceUrl: request.sourceUrl,
      );
    } catch (_) {
      _logger.log(
        'engine evaluate failed uri=${uri.host}${uri.path} type=${request.resourceType}',
      );
      blockedByEngine = false;
    }

    final decision = AdblockDecision(
      blocked: blockedByEngine,
      reason: blockedByEngine ? 'engine_match' : 'allowed',
      matchedRule: blockedByEngine ? uri.toString() : null,
    );
    _writeCache(decisionCacheKey, decision);
    return decision;
  }

  bool _isAllowlisted(String host) {
    final normalizedHost = host.toLowerCase();
    return _config.allowlistedHosts.any(
      (candidate) =>
          normalizedHost == candidate || normalizedHost.endsWith('.$candidate'),
    );
  }

  bool _isBlocklisted(String host) {
    final normalizedHost = host.toLowerCase();
    return _config.blocklistedHosts.any(
      (candidate) =>
          normalizedHost == candidate || normalizedHost.endsWith('.$candidate'),
    );
  }

  bool _isPrimaryPlaybackMediaRequest(Uri uri, String normalizedType) {
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

  bool _isSkippableStaticResource(Uri uri, String normalizedType) {
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    final isYouTubeHost =
        host == 'youtube.com' || host.endsWith('.youtube.com');
    if (!isYouTubeHost) {
      return false;
    }

    if (path == '/favicon.ico' || path == '/static/favicon.ico') {
      return true;
    }
    if (path.startsWith('/s/search/audio/')) {
      return true;
    }
    if (path == '/api/stats/watchtime' || path == '/api/stats/qoe') {
      return true;
    }
    if ((normalizedType == 'script' || normalizedType == 'stylesheet') &&
        (path.startsWith('/s/_/ytmweb/_/js/') ||
            path.startsWith('/s/_/ytmweb/_/ss/') ||
            path.startsWith('/s/player/'))) {
      return true;
    }
    return false;
  }

  bool _isYouTubeTelemetryFastPath(Uri uri, String normalizedType) {
    if (normalizedType == 'document' || normalizedType == 'subdocument') {
      return false;
    }
    final host = uri.host.toLowerCase();
    final isYouTubeHost =
        host == 'youtube.com' || host.endsWith('.youtube.com');
    if (!isYouTubeHost) {
      return false;
    }
    final path = uri.path.toLowerCase();
    // Keep these noisy first-party telemetry paths fail-open, including
    // trailing-slash variants, to avoid retry storms during watch transitions.
    return path == '/pagead/interaction' ||
        path.startsWith('/pagead/interaction/') ||
        path == '/pagead/adview' ||
        path.startsWith('/pagead/adview/') ||
        path == '/ptracking' ||
        path.startsWith('/ptracking/');
  }

  bool _isGoogleVideoAdPlaybackRequest(Uri uri) {
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    final isGoogleVideoHost =
        host == 'googlevideo.com' || host.endsWith('.googlevideo.com');
    if (!isGoogleVideoHost || !path.contains('/videoplayback')) {
      return false;
    }
    final rawQuery = uri.query;
    if (_containsAnyQueryKeyInRawQuery(rawQuery, _googleVideoAdQueryKeys)) {
      return true;
    }
    if (_containsAdLikeQueryKey(rawQuery)) {
      return true;
    }
    return _containsQueryKeyWithValuePrefix(
      rawQuery,
      key: 'ctier',
      valuePrefix: 'a',
    );
  }

  bool _containsAnyQueryKeyInRawQuery(String rawQuery, List<String> keys) {
    if (rawQuery.isEmpty) {
      return false;
    }
    final normalizedQuery = '&${rawQuery.toLowerCase()}&';
    for (final key in keys) {
      if (normalizedQuery.contains('&$key=') ||
          normalizedQuery.contains('&$key&')) {
        return true;
      }
    }
    return false;
  }

  bool _containsAdLikeQueryKey(String rawQuery) {
    if (rawQuery.isEmpty) {
      return false;
    }
    for (final segment in rawQuery.split('&')) {
      if (segment.isEmpty) {
        continue;
      }
      final separator = segment.indexOf('=');
      final rawKey = separator == -1
          ? segment
          : segment.substring(0, separator);
      final key = _safeDecodeQueryComponent(rawKey).toLowerCase();
      if (_isAdLikeQueryKey(key)) {
        return true;
      }
    }
    return false;
  }

  bool _isAdLikeQueryKey(String key) {
    if (key.isEmpty) {
      return false;
    }
    if (key == 'oad' || key == 'ad') {
      return true;
    }
    if (_googleVideoAdQueryKeys.contains(key)) {
      return true;
    }
    if (key.startsWith('ad_') || key.startsWith('ads_')) {
      return true;
    }
    if (key.contains('_ad_') ||
        key.endsWith('_ad') ||
        key.endsWith('adid') ||
        key.endsWith('adsid')) {
      return true;
    }
    return false;
  }

  bool _containsQueryKeyWithValuePrefix(
    String rawQuery, {
    required String key,
    required String valuePrefix,
  }) {
    if (rawQuery.isEmpty) {
      return false;
    }
    final normalizedKey = key.trim().toLowerCase();
    final normalizedValuePrefix = valuePrefix.trim().toLowerCase();
    if (normalizedKey.isEmpty || normalizedValuePrefix.isEmpty) {
      return false;
    }
    for (final segment in rawQuery.split('&')) {
      if (segment.isEmpty) {
        continue;
      }
      final separator = segment.indexOf('=');
      final rawKey = separator == -1
          ? segment
          : segment.substring(0, separator);
      final decodedKey = _safeDecodeQueryComponent(rawKey).toLowerCase();
      if (decodedKey != normalizedKey) {
        continue;
      }
      if (separator == -1) {
        return false;
      }
      final rawValue = segment.substring(separator + 1);
      final decodedValue = _safeDecodeQueryComponent(rawValue).toLowerCase();
      return decodedValue.startsWith(normalizedValuePrefix);
    }
    return false;
  }

  String _safeDecodeQueryComponent(String value) {
    try {
      return Uri.decodeQueryComponent(value);
    } catch (_) {
      return value;
    }
  }

  bool _isThirdPartyRequest({
    required String requestHost,
    required String? sourceHost,
  }) {
    if (sourceHost == null || sourceHost.isEmpty) {
      return false;
    }
    final normalizedRequestHost = requestHost.toLowerCase();
    final normalizedSourceHost = sourceHost.toLowerCase();
    return !(normalizedRequestHost == normalizedSourceHost ||
        normalizedRequestHost.endsWith('.$normalizedSourceHost') ||
        normalizedSourceHost.endsWith('.$normalizedRequestHost'));
  }

  bool _isCoreYouTubeHost(String host) {
    final normalizedHost = host.toLowerCase();
    if (normalizedHost == 'youtube.com' ||
        normalizedHost.endsWith('.youtube.com')) {
      return true;
    }
    if (normalizedHost == 'googlevideo.com' ||
        normalizedHost.endsWith('.googlevideo.com')) {
      return true;
    }
    if (normalizedHost == 'ytimg.com' ||
        normalizedHost.endsWith('.ytimg.com')) {
      return true;
    }
    if (normalizedHost == 'youtubei.googleapis.com') {
      return true;
    }
    return normalizedHost == 'googleapis.com' ||
        normalizedHost.endsWith('.googleapis.com');
  }

  String _cacheKey(AdblockRequestContext request) {
    final sourceHost = request.sourceUrl?.host.toLowerCase() ?? 'none';
    return '${request.resourceType.toLowerCase()}|${request.uri.scheme.toLowerCase()}://${request.uri.host.toLowerCase()}${request.uri.path}?${request.uri.query}|$sourceHost|sw=${request.fromServiceWorker}';
  }

  AdblockDecision? _readCache(String key) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final entry = _decisionCache.remove(key);
    if (entry == null) {
      return null;
    }
    if (entry.expiresAtMs <= now) {
      return null;
    }
    _decisionCache[key] = entry;
    return AdblockDecision(
      blocked: entry.blocked,
      reason: entry.reason,
      matchedRule: entry.matchedRule,
      fromCache: true,
    );
  }

  void _writeCache(String key, AdblockDecision decision) {
    _decisionCache.remove(key);
    _decisionCache[key] = _DecisionCacheEntry(
      blocked: decision.blocked,
      reason: decision.reason,
      matchedRule: decision.matchedRule,
      expiresAtMs: DateTime.now().add(_decisionCacheTtl).millisecondsSinceEpoch,
    );
    if (_decisionCache.length > _decisionCacheLimit) {
      _decisionCache.remove(_decisionCache.keys.first);
    }
  }
}

class _DecisionCacheEntry {
  const _DecisionCacheEntry({
    required this.blocked,
    required this.reason,
    required this.matchedRule,
    required this.expiresAtMs,
  });

  final bool blocked;
  final String reason;
  final String? matchedRule;
  final int expiresAtMs;
}
