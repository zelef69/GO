import 'dart:async';
import 'dart:collection';

import '../../domain_lock/domain_policy_service.dart';
import '../adblock_engine_bridge.dart';
import '../crowd/storage/learned_signature_repository.dart';
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
    required this.adShowing,
    this.playbackStalled = false,
    this.adSignalKey,
  });

  final Uri uri;
  final String resourceType;
  final Uri? sourceUrl;
  final bool fromServiceWorker;
  final bool adShowing;
  final bool playbackStalled;
  final String? adSignalKey;
}

class AdblockDecision {
  const AdblockDecision({
    required this.blocked,
    required this.reason,
    this.matchedRule,
    this.redirectDataUrl,
    this.rewrittenUrl,
    this.fromCache = false,
  });

  final bool blocked;
  final String reason;
  final String? matchedRule;
  final String? redirectDataUrl;
  final String? rewrittenUrl;
  final bool fromCache;
}

class RequestBlocker {
  RequestBlocker({
    required DomainPolicyService domainPolicyService,
    required AdblockDebugLogger logger,
    required AdblockMetricsCollector metrics,
    LearnedSignatureRepository? learnedSignatureRepository,
  }) : _domainPolicyService = domainPolicyService,
       _logger = logger,
       _metrics = metrics,
       _learnedSignatureRepository = learnedSignatureRepository;

  static const int _decisionCacheLimit = 2048;
  static const Duration _decisionCacheTtl = Duration(seconds: 25);
  static const int _maxGoogleVideoAllowTraceLogs = 240;
  static const int _maxGoogleVideoAdShowingMarkerLogs = 120;
  static const int _maxGoogleVideoPreAdMarkerLogs = 80;
  static const bool _enableGoogleVideoFullQueryLogs = false;
  static const bool _enableAdShowingGuardedGoogleVideoBlock = true;
  static const bool _enableGoogleVideoBrowsePrefetchGuard = true;
  static const bool _enablePageAdInteractionGuard = true;
  static const bool _enableAdSignalWindowGuard = true;
  static const int _maxSoftBlockGuardLogs = 80;
  static const Duration _softBlockGuardWindow = Duration(seconds: 4);
  static const int _softBlockGuardThreshold = 6;
  static const Duration _softBlockGuardCooldown = Duration(seconds: 8);
  static const int _maxSoftBlockGuardStateEntries = 240;
  static const Duration _adSignalWindow = Duration(seconds: 12);
  static const int _maxAdSignalStateEntries = 320;
  static const int _maxAdSignalLogs = 80;
  static const int _decisionStatsLogInterval = 180;
  static const List<String> _pageAdInteractionGuardQueryKeys = <String>[
    'ad_mt',
    'acvw',
    'label',
    'ai',
    'cid',
    'sigh',
    'adk',
    'adurl',
    'ad_url',
    'adid',
  ];
  static const List<String> _googleVideoHardAdQueryKeys = <String>[
    'oad',
    'ads_payload',
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
    'ad_mt',
    'ad_eurl',
  ];
  static const List<String> _googleVideoSoftAdQueryKeysStrong = <String>[
    'ad_url',
    'adurl',
    'ad_break',
    'ad_break_id',
    'adpod',
    'ad_pod',
    'ad_campaign',
    'ad_cid',
    'ad_placement',
    'adplacement',
    'ad_source',
    'adserver',
    'ad_server',
  ];
  static const List<String> _googleVideoSoftAdQueryKeysWeak = <String>[
    'ad_slot',
    'adslot',
    'adslotname',
    'adcontext',
    'ad_context',
    'adcontexturl',
    'ad_context_url',
    'adunit',
    'ad_unit',
    'preroll',
    'midroll',
    'postroll',
  ];
  static const List<String> _googleVideoSoftAdQueryKeys = <String>[
    ..._googleVideoSoftAdQueryKeysStrong,
    ..._googleVideoSoftAdQueryKeysWeak,
  ];
  static const List<String> _googleVideoAggressiveOnlyQueryKeys = <String>[
    'ad_url',
    'adurl',
    'ad_slot',
    'adslot',
    'adslotname',
    'adcontext',
    'ad_context',
    'adcontexturl',
    'ad_context_url',
    'ad_break',
    'ad_break_id',
    'adpod',
    'ad_pod',
    'adunit',
    'ad_unit',
    'ad_slot',
    'ad_campaign',
    'ad_cid',
    'ad_placement',
    'adplacement',
    'ad_source',
    'adserver',
    'ad_server',
    'adunit',
    'ad_unit',
  ];
  static const List<String> _googleVideoLeakedAdSignalKeys = <String>[
    'svpuc',
    'sabr',
    'rqh',
  ];
  static const List<String> _googleVideoLeakedSparamsTokens = <String>[
    'svpuc',
    'sabr',
    'rqh',
  ];
  static const List<String> _googleVideoContentSignatureKeys = <String>[
    'itag',
    'mime',
    'clen',
    'dur',
  ];
  static const List<String> _googleVideoAggressiveGuardValueTokens = <String>[
    'preroll',
    'midroll',
    'postroll',
    'adbreak',
    'ad_break',
    'adslot',
    'ad_slot',
    'adunit',
    'ad_unit',
    'videoad',
    'companionad',
    'doubleclick',
    'googlesyndication',
    'googleadservices',
    'advertiser',
    'vast',
  ];
  static const List<String> _googleVideoAggressiveGuardQueryKeys = <String>[
    'adpod',
    'ad_pod',
    'ad_break_id',
    'ad_campaign',
    'ad_cid',
    'ad_placement',
    'adplacement',
    'ad_source',
    'adserver',
    'ad_server',
    'adunit',
    'ad_unit',
    'adslot',
    'ad_slot',
    'adslotname',
    'adcontext',
    'ad_context',
    'adcontexturl',
    'ad_context_url',
  ];
  static const List<String> _googleVideoAdLabelValues = <String>[
    'admute',
    'part2viewed',
    'videoplaytime25',
    'videoplaytime50',
    'videoplaytime75',
    'videoplaytime100',
  ];
  static const List<String> _primaryPlaybackRequiredQueryKeys = <String>[
    'id',
    'itag',
  ];
  static const List<String> _primaryPlaybackContentSignalKeys = <String>[
    'expire',
    'mime',
    'clen',
    'dur',
    'ei',
    'ip',
  ];

  final DomainPolicyService _domainPolicyService;
  final AdblockDebugLogger _logger;
  final AdblockMetricsCollector _metrics;
  final LearnedSignatureRepository? _learnedSignatureRepository;
  final LinkedHashMap<String, _DecisionCacheEntry> _decisionCache =
      LinkedHashMap<String, _DecisionCacheEntry>();
  final LinkedHashMap<String, _SoftBlockGuardState> _softBlockGuardStates =
      LinkedHashMap<String, _SoftBlockGuardState>();
  final LinkedHashMap<String, _AdSignalState> _adSignalStates =
      LinkedHashMap<String, _AdSignalState>();
  final Map<String, int> _decisionReasonCounts = <String, int>{};
  int _googleVideoAllowTraceCount = 0;
  int _googleVideoAdShowingMarkerLogCount = 0;
  int _googleVideoPreAdMarkerLogCount = 0;
  int _softBlockGuardLogCount = 0;
  int _adSignalLogCount = 0;
  int _decisionStatsSampleCount = 0;
  int _decisionStatsBlockedCount = 0;
  AdblockConfig _config = AdblockConfig.defaults(
    enabled: true,
    debugMode: false,
  );
  bool _firstPartyHeuristicProfileEnabled = false;
  AdblockEngineBridge? _engine;

  void setConfig(AdblockConfig config) {
    _config = config;
    _decisionCache.clear();
    _softBlockGuardStates.clear();
    _adSignalStates.clear();
    _decisionReasonCounts.clear();
    _googleVideoAllowTraceCount = 0;
    _googleVideoAdShowingMarkerLogCount = 0;
    _googleVideoPreAdMarkerLogCount = 0;
    _softBlockGuardLogCount = 0;
    _adSignalLogCount = 0;
    _decisionStatsSampleCount = 0;
    _decisionStatsBlockedCount = 0;
  }

  void setEngine(AdblockEngineBridge engine) {
    _engine = engine;
  }

  void setFirstPartyHeuristicProfile(bool enabled) {
    if (_firstPartyHeuristicProfileEnabled == enabled) {
      return;
    }
    _firstPartyHeuristicProfileEnabled = enabled;
    _decisionCache.clear();
    _softBlockGuardStates.clear();
    _adSignalStates.clear();
    _logger.log('first_party_heuristic_profile enabled=$enabled');
  }

  void clearCache() {
    _decisionCache.clear();
    _softBlockGuardStates.clear();
    _adSignalStates.clear();
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
    _recordDecisionStats(result);
    return result;
  }

  Future<AdblockDecision> _evaluateInternal(
    AdblockRequestContext request,
  ) async {
    final uri = request.uri;
    final normalizedType = request.resourceType.toLowerCase();

    _recordCrowdPlaybackStallFeedback(request);

    if (!_config.enabled) {
      return const AdblockDecision(blocked: false, reason: 'disabled');
    }

    if (_isAllowlisted(uri.host)) {
      return const AdblockDecision(blocked: false, reason: 'allowlisted_host');
    }

    if (_isBlocklisted(uri.host)) {
      return _finalizeBlockedDecision(
        request,
        AdblockDecision(
          blocked: true,
          reason: 'blocklisted_host',
          matchedRule: uri.host,
        ),
      );
    }

    if (!_domainPolicyService.isRequestAllowed(uri)) {
      return _finalizeBlockedDecision(
        request,
        AdblockDecision(
          blocked: true,
          reason: 'domain_policy',
          matchedRule: uri.host,
        ),
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

    final learnedPrecheck = _evaluateCrowdPrecheck(request);
    if (learnedPrecheck != null) {
      return learnedPrecheck;
    }

    // Guard pagead interaction when the request clearly carries ad markers.
    // Keep this strict to avoid disturbing non-ad telemetry traffic.
    if (_shouldGuardBlockYouTubePageAdInteraction(request, normalizedType)) {
      _recordAdSignal(request, source: 'pagead_interaction_guard');
      return _finalizeBlockedDecision(
        request,
        AdblockDecision(
          blocked: true,
          reason: 'pagead_interaction_guard',
          matchedRule: uri.toString(),
        ),
      );
    }

    // Keep high-churn first-party telemetry fail-open otherwise to prevent
    // retry storms that can trap YouTube in long ad-transition black screens.
    if (_isYouTubeTelemetryFastPath(uri, normalizedType)) {
      return const AdblockDecision(
        blocked: false,
        reason: 'youtube_telemetry_fast_path',
      );
    }

    // Tier-1: hard ad markers on googlevideo playback. These are stable
    // enough to block immediately without relying on transient player state.
    if (_isGoogleVideoHardAdPlaybackRequest(uri)) {
      _recordAdSignal(request, source: 'googlevideo_hard');
      return _finalizeBlockedDecision(
        request,
        AdblockDecision(
          blocked: true,
          reason: 'googlevideo_ad_query_hard',
          matchedRule: uri.toString(),
        ),
      );
    }

    // Recovery guard: when player is in a stalled state, temporarily fail-open
    // googlevideo streams so playback can recover from readyState=0 loops.
    if (request.playbackStalled &&
        _isGoogleVideoPlaybackRequest(uri) &&
        (normalizedType == 'media' || normalizedType == 'xmlhttprequest')) {
      _logGoogleVideoAllowTrace(request, reason: 'playback_stall_backoff');
      return const AdblockDecision(
        blocked: false,
        reason: 'playback_stall_backoff',
      );
    }

    // Tier-2 soft guard: prefetch-style googlevideo XHR from browse surfaces.
    // This is useful for ad warmup requests but can be noisy, so apply a
    // cooldown guard when repeated blocks happen in a short burst.
    if (_shouldBlockGoogleVideoBrowsePrefetch(request, normalizedType)) {
      if (_shouldBypassSoftBlockWithCooldown(
        request,
        guard: 'browse_prefetch',
      )) {
        _logGoogleVideoAllowTrace(
          request,
          reason: 'soft_guard_cooldown_browse_prefetch',
        );
      } else {
        _recordSoftBlock(request, guard: 'browse_prefetch');
        return _finalizeBlockedDecision(
          request,
          AdblockDecision(
            blocked: true,
            reason: 'googlevideo_browse_prefetch_guard',
            matchedRule: uri.toString(),
          ),
        );
      }
    }

    // Tier-2 soft guard: block ad-marked streams only while ad is actively
    // showing. Guarded by cooldown to avoid white-screen lockups.
    if (_shouldGuardBlockGoogleVideoRequest(request, normalizedType)) {
      if (_shouldBypassSoftBlockWithCooldown(request, guard: 'ad_showing')) {
        _logGoogleVideoAllowTrace(
          request,
          reason: 'soft_guard_cooldown_ad_showing',
        );
      } else {
        _recordSoftBlock(request, guard: 'ad_showing');
        return _finalizeBlockedDecision(
          request,
          AdblockDecision(
            blocked: true,
            reason: 'googlevideo_ad_query_soft',
            matchedRule: uri.toString(),
          ),
        );
      }
    }

    // Always allow primary googlevideo playback streams to avoid player
    // deadlocks/black-screen stalls while YouTube switches streams.
    // Keep this strict: only clearly content-like media requests pass fast-path.
    if (_isPrimaryPlaybackMediaRequest(uri, normalizedType)) {
      _logGoogleVideoAllowTrace(request, reason: 'media_fast_path');
      return const AdblockDecision(blocked: false, reason: 'media_fast_path');
    }

    final decisionCacheKey = _cacheKey(request);
    final cached = _readCache(decisionCacheKey);
    if (cached != null) {
      if (!cached.blocked) {
        _logGoogleVideoAllowTrace(request, reason: 'cache_${cached.reason}');
      }
      return cached;
    }

    if (YouTubeAdRequestMatcher.matches(uri)) {
      if (_shouldRecordHeuristicAdSignal(uri)) {
        _recordAdSignal(request, source: 'heuristic_matcher');
      }
      final decision = AdblockDecision(
        blocked: true,
        reason: 'heuristic_matcher',
        matchedRule: uri.toString(),
      );
      _writeCache(decisionCacheKey, decision);
      return _finalizeBlockedDecision(request, decision);
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
      return _finalizeBlockedDecision(request, decision);
    }

    // Engine-first for first-party requests. Keep only explicit fast-path
    // guards above and let adblock-rust make the final decision here.

    final engine = _engine;
    if (engine == null) {
      const decision = AdblockDecision(
        blocked: false,
        reason: 'engine_not_ready',
      );
      _logGoogleVideoAllowTrace(request, reason: decision.reason);
      return decision;
    }

    var engineResult = AdblockEngineRequestResult.allow();
    try {
      engineResult = await engine.evaluateRequestDetailed(
        uri,
        resourceType: request.resourceType,
        sourceUrl: request.sourceUrl,
      );
    } catch (_) {
      _logger.log(
        'engine evaluate failed uri=${uri.host}${uri.path} type=${request.resourceType}',
      );
      engineResult = AdblockEngineRequestResult.allow();
    }

    final blockedByEngine = engineResult.blocked;
    final hasRedirect = (engineResult.redirectDataUrl ?? '').isNotEmpty;
    final hasRewrite = (engineResult.rewrittenUrl ?? '').isNotEmpty;
    final decision = AdblockDecision(
      blocked: blockedByEngine,
      reason: hasRedirect
          ? 'engine_redirect'
          : blockedByEngine
          ? 'engine_match'
          : hasRewrite
          ? 'engine_rewrite'
          : 'allowed',
      matchedRule:
          engineResult.matchedRule ?? (blockedByEngine ? uri.toString() : null),
      redirectDataUrl: engineResult.redirectDataUrl,
      rewrittenUrl: engineResult.rewrittenUrl,
    );
    if (!decision.blocked) {
      _logGoogleVideoAllowTrace(request, reason: 'engine_allow');
    } else {
      _recordCrowdDecision(request, decision);
    }
    _writeCache(decisionCacheKey, decision);
    return decision;
  }

  void onPlaybackDebugSignal(Map<String, dynamic> payload, {Uri? pageUri}) {
    if (!_config.crowdLearningEnabled) {
      return;
    }
    final repository = _learnedSignatureRepository;
    if (repository == null) {
      return;
    }
    unawaited(repository.recordPlaybackDebugSignal(payload, pageUri: pageUri));
  }

  AdblockDecision? _evaluateCrowdPrecheck(AdblockRequestContext request) {
    if (!_config.crowdLearningEnabled || !_config.crowdPrecheckEnabled) {
      return null;
    }
    final repository = _learnedSignatureRepository;
    if (repository == null) {
      return null;
    }
    final match = repository.precheck(
      uri: request.uri,
      resourceType: request.resourceType,
      sourceUrl: request.sourceUrl,
      adShowing: request.adShowing,
      playbackStalled: request.playbackStalled,
    );
    if (!match.matched) {
      return null;
    }
    return AdblockDecision(
      blocked: true,
      reason: 'learned_signature',
      matchedRule: match.sigHash,
    );
  }

  AdblockDecision _finalizeBlockedDecision(
    AdblockRequestContext request,
    AdblockDecision decision,
  ) {
    _recordCrowdDecision(request, decision);
    return decision;
  }

  void _recordCrowdDecision(
    AdblockRequestContext request,
    AdblockDecision decision,
  ) {
    if (!_config.crowdLearningEnabled || !decision.blocked) {
      return;
    }
    if (decision.reason == 'learned_signature') {
      return;
    }
    final repository = _learnedSignatureRepository;
    if (repository == null) {
      return;
    }
    unawaited(
      repository.recordDecision(
        uri: request.uri,
        resourceType: request.resourceType,
        sourceUrl: request.sourceUrl,
        adShowing: request.adShowing,
        blocked: decision.blocked,
        reason: decision.reason,
        matchedRule: decision.matchedRule,
      ),
    );
  }

  void _recordCrowdPlaybackStallFeedback(AdblockRequestContext request) {
    if (!_config.crowdLearningEnabled || !request.playbackStalled) {
      return;
    }
    final repository = _learnedSignatureRepository;
    if (repository == null) {
      return;
    }
    unawaited(
      repository.recordPlaybackStall(
        uri: request.uri,
        resourceType: request.resourceType,
        sourceUrl: request.sourceUrl,
      ),
    );
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
    if (normalizedType != 'media') {
      return false;
    }
    if (!_isGoogleVideoPlaybackRequest(uri)) {
      return false;
    }
    final rawQuery = uri.query;
    if (!_containsAllQueryKeysInRawQuery(
      rawQuery,
      _primaryPlaybackRequiredQueryKeys,
    )) {
      return false;
    }
    if (!_containsAnyQueryKeyInRawQuery(
      rawQuery,
      _primaryPlaybackContentSignalKeys,
    )) {
      return false;
    }
    if (_containsAnyQueryKeyInRawQuery(rawQuery, _googleVideoHardAdQueryKeys) ||
        _containsAnyQueryKeyInRawQuery(rawQuery, _googleVideoSoftAdQueryKeys)) {
      return false;
    }
    if (_containsAdLikeQueryKey(rawQuery)) {
      return false;
    }
    if (_containsQueryKeyWithValuePrefix(
      rawQuery,
      key: 'ctier',
      valuePrefix: 'a',
    )) {
      return false;
    }
    if (_containsQueryKeyWithAnyValue(
      rawQuery,
      key: 'label',
      candidateValues: _googleVideoAdLabelValues,
    )) {
      return false;
    }
    return true;
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
    final baseTelemetryPath =
        path == '/pagead/interaction' ||
        path.startsWith('/pagead/interaction/') ||
        path == '/pagead/adview' ||
        path.startsWith('/pagead/adview/') ||
        path == '/ptracking' ||
        path.startsWith('/ptracking/');
    if (baseTelemetryPath) {
      return true;
    }
    if (!_firstPartyHeuristicProfileEnabled) {
      return false;
    }
    // First-party heuristic profile: keep high-churn first-party telemetry
    // fail-open to avoid retry storms during watch/ad transitions.
    return path == '/youtubei/v1/log_event' ||
        path.startsWith('/youtubei/v1/log_event/') ||
        path == '/api/stats/atr' ||
        path.startsWith('/api/stats/atr/') ||
        path == '/api/stats/ad' ||
        path.startsWith('/api/stats/ad/') ||
        path == '/api/stats/ads' ||
        path.startsWith('/api/stats/ads/');
  }

  bool _shouldRecordHeuristicAdSignal(Uri uri) {
    if (!_isYouTubeHost(uri.host.toLowerCase())) {
      return false;
    }
    final path = uri.path.toLowerCase();
    if (path.contains('/api/stats/ad') && !_firstPartyHeuristicProfileEnabled) {
      return false;
    }
    return path.contains('/player/ad_break') ||
        path.contains('/pagead/') ||
        path.contains('/api/stats/ad');
  }

  bool _shouldGuardBlockYouTubePageAdInteraction(
    AdblockRequestContext request,
    String normalizedType,
  ) {
    if (!_enablePageAdInteractionGuard) {
      return false;
    }
    if (normalizedType == 'document' || normalizedType == 'subdocument') {
      return false;
    }
    final uri = request.uri;
    if (!_isYouTubeHost(uri.host.toLowerCase())) {
      return false;
    }
    final path = uri.path.toLowerCase();
    final isPageAdInteractionPath =
        path == '/pagead/interaction' ||
        path.startsWith('/pagead/interaction/') ||
        path == '/pagead/adview' ||
        path.startsWith('/pagead/adview/');
    if (!isPageAdInteractionPath) {
      return false;
    }
    final rawQuery = uri.query;
    if (rawQuery.isEmpty) {
      return false;
    }
    final hasAdMarkers =
        _containsAnyQueryKeyInRawQuery(
          rawQuery,
          _pageAdInteractionGuardQueryKeys,
        ) ||
        _containsAdLikeQueryKey(rawQuery) ||
        _containsQueryKeyWithValuePrefix(
          rawQuery,
          key: 'label',
          valuePrefix: 'videoplaytime',
        ) ||
        _containsQueryKeyWithValuePrefix(
          rawQuery,
          key: 'label',
          valuePrefix: 'ad',
        );
    if (!hasAdMarkers) {
      return false;
    }
    if (request.adShowing) {
      return true;
    }
    if (_isYouTubeWatchSurfaceSource(request.sourceUrl)) {
      return true;
    }
    return false;
  }

  bool _isGoogleVideoHardAdPlaybackRequest(Uri uri) {
    if (!_isGoogleVideoPlaybackRequest(uri)) {
      return false;
    }
    final rawQuery = uri.query;
    return _hasGoogleVideoHardAdMarkers(rawQuery);
  }

  bool _isGoogleVideoPlaybackRequest(Uri uri) {
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    final isGoogleVideoHost =
        host == 'googlevideo.com' || host.endsWith('.googlevideo.com');
    return isGoogleVideoHost && path.contains('/videoplayback');
  }

  bool _shouldGuardBlockGoogleVideoRequest(
    AdblockRequestContext request,
    String normalizedType,
  ) {
    if (!_enableAdShowingGuardedGoogleVideoBlock || !request.adShowing) {
      return false;
    }
    if (request.playbackStalled) {
      return false;
    }
    if (normalizedType != 'media' && normalizedType != 'xmlhttprequest') {
      return false;
    }
    final uri = request.uri;
    if (!_isGoogleVideoPlaybackRequest(uri)) {
      return false;
    }
    final rawQuery = uri.query;
    if (rawQuery.isEmpty) {
      return false;
    }
    if (_hasGoogleVideoConservativeSoftAdMarkers(rawQuery)) {
      return true;
    }
    if (!_isAdSignalActive(request)) {
      return false;
    }
    return _hasGoogleVideoAggressiveSoftAdMarkers(rawQuery);
  }

  bool _shouldBlockGoogleVideoBrowsePrefetch(
    AdblockRequestContext request,
    String normalizedType,
  ) {
    if (!_enableGoogleVideoBrowsePrefetchGuard || request.adShowing) {
      return false;
    }
    if (request.playbackStalled) {
      return false;
    }
    if (normalizedType != 'xmlhttprequest') {
      return false;
    }
    if (!_isGoogleVideoPlaybackRequest(request.uri)) {
      return false;
    }
    if (!_isYouTubeBrowseSurfaceSource(request.sourceUrl)) {
      return false;
    }
    if (_isYouTubeWatchSurfaceSource(request.sourceUrl)) {
      return false;
    }
    final rawQuery = request.uri.query;
    if (rawQuery.isEmpty) {
      return true;
    }
    if (_hasGoogleVideoHardAdMarkers(rawQuery) ||
        _hasGoogleVideoConservativeSoftAdMarkers(rawQuery)) {
      return true;
    }
    return !_containsAllQueryKeysInRawQuery(
      rawQuery,
      _primaryPlaybackRequiredQueryKeys,
    );
  }

  bool _hasGoogleVideoHardAdMarkers(String rawQuery) {
    if (rawQuery.isEmpty) {
      return false;
    }
    if (_containsAnyQueryKeyInRawQuery(rawQuery, _googleVideoHardAdQueryKeys)) {
      return true;
    }
    if (_containsAdLikeQueryKey(rawQuery)) {
      return true;
    }
    if (_containsQueryKeyWithAnyValue(
      rawQuery,
      key: 'label',
      candidateValues: _googleVideoAdLabelValues,
    )) {
      return true;
    }
    return _containsQueryKeyWithValuePrefix(
      rawQuery,
      key: 'ctier',
      valuePrefix: 'a',
    );
  }

  bool _hasGoogleVideoConservativeSoftAdMarkers(String rawQuery) {
    if (rawQuery.isEmpty) {
      return false;
    }
    if (_containsAnyQueryKeyInRawQuery(
      rawQuery,
      _googleVideoSoftAdQueryKeysStrong,
    )) {
      return true;
    }
    final weakHits = _countQueryKeyHitsInRawQuery(
      rawQuery,
      _googleVideoSoftAdQueryKeysWeak,
      maxHits: 2,
    );
    // Require multiple weak markers to avoid over-blocking content streams.
    return weakHits >= 2;
  }

  bool _hasGoogleVideoAggressiveSoftAdMarkers(String rawQuery) {
    if (rawQuery.isEmpty) {
      return false;
    }
    if (_hasGoogleVideoConservativeSoftAdMarkers(rawQuery)) {
      return true;
    }
    if (_containsAnyQueryKeyInRawQuery(
      rawQuery,
      _googleVideoAggressiveOnlyQueryKeys,
    )) {
      return true;
    }
    if (_containsAnyQueryKeyInRawQuery(
      rawQuery,
      _googleVideoAggressiveGuardQueryKeys,
    )) {
      return true;
    }
    if (_containsAdLikeQueryValue(rawQuery)) {
      return true;
    }
    if (_containsQueryKeyWithValuePrefix(
      rawQuery,
      key: 'label',
      valuePrefix: 'ad',
    )) {
      return true;
    }
    if (_containsQueryKeyWithValuePrefix(
      rawQuery,
      key: 'label',
      valuePrefix: 'videoplaytime',
    )) {
      return true;
    }
    return _matchesLeakedGoogleVideoAdPattern(rawQuery);
  }

  bool _matchesLeakedGoogleVideoAdPattern(String rawQuery) {
    if (rawQuery.isEmpty) {
      return false;
    }
    final isMwebClient = _containsQueryKeyWithAnyValue(
      rawQuery,
      key: 'c',
      candidateValues: const <String>['mweb'],
    );
    if (!isMwebClient) {
      return false;
    }
    final hasLeakedSignals = _containsAnyQueryKeyInRawQuery(
      rawQuery,
      _googleVideoLeakedAdSignalKeys,
    );
    if (!hasLeakedSignals) {
      return false;
    }
    final hasLeakedSparamsSignature = _containsQueryKeyValueContainingAllTokens(
      rawQuery,
      key: 'sparams',
      tokens: _googleVideoLeakedSparamsTokens,
    );
    if (!hasLeakedSparamsSignature) {
      return false;
    }
    // Real leaked ad request did not carry content stream identifiers such as
    // itag/mime/clen/dur. Keep this guard to reduce false positives.
    final hasContentSignature = _containsAnyQueryKeyInRawQuery(
      rawQuery,
      _googleVideoContentSignatureKeys,
    );
    return !hasContentSignature;
  }

  bool _isYouTubeWatchSurfaceSource(Uri? sourceUrl) {
    if (sourceUrl == null) {
      return false;
    }
    final host = sourceUrl.host.toLowerCase();
    if (!_isYouTubeHost(host)) {
      return false;
    }
    final path = sourceUrl.path.toLowerCase();
    return path == '/watch' ||
        path.startsWith('/watch') ||
        path.startsWith('/shorts/') ||
        path.startsWith('/live/');
  }

  bool _isYouTubeBrowseSurfaceSource(Uri? sourceUrl) {
    if (sourceUrl == null) {
      return false;
    }
    final host = sourceUrl.host.toLowerCase();
    if (!_isYouTubeHost(host)) {
      return false;
    }
    final path = sourceUrl.path.toLowerCase();
    if (path.isEmpty || path == '/') {
      return true;
    }
    return path.startsWith('/results') || path.startsWith('/feed/');
  }

  bool _isYouTubeHost(String host) {
    return host == 'youtube.com' || host.endsWith('.youtube.com');
  }

  bool _shouldBypassSoftBlockWithCooldown(
    AdblockRequestContext request, {
    required String guard,
  }) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final key = _softBlockGuardKey(request);
    final state = _softBlockGuardStates.remove(key);
    if (state == null) {
      return false;
    }
    if (state.cooldownUntilMs <= nowMs) {
      if (state.windowStartedAtMs + _softBlockGuardWindow.inMilliseconds <=
          nowMs) {
        return false;
      }
      _softBlockGuardStates[key] = state;
      return false;
    }
    _softBlockGuardStates[key] = state;
    if (_softBlockGuardLogCount < _maxSoftBlockGuardLogs) {
      _softBlockGuardLogCount += 1;
      final remainingMs = state.cooldownUntilMs - nowMs;
      _logger.log(
        'soft_guard bypass key=$key guard=$guard cooldownLeftMs=$remainingMs',
      );
    }
    return true;
  }

  void _recordSoftBlock(
    AdblockRequestContext request, {
    required String guard,
  }) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final key = _softBlockGuardKey(request);
    final existing = _softBlockGuardStates.remove(key);
    if (existing == null ||
        existing.cooldownUntilMs <= nowMs &&
            existing.windowStartedAtMs + _softBlockGuardWindow.inMilliseconds <=
                nowMs) {
      _softBlockGuardStates[key] = _SoftBlockGuardState(
        windowStartedAtMs: nowMs,
        blockCountInWindow: 1,
        cooldownUntilMs: 0,
      );
      _trimSoftBlockGuardStates();
      return;
    }

    var nextCount = existing.blockCountInWindow + 1;
    var nextCooldownUntilMs = existing.cooldownUntilMs;
    var nextWindowStartedAtMs = existing.windowStartedAtMs;
    if (existing.windowStartedAtMs + _softBlockGuardWindow.inMilliseconds <=
        nowMs) {
      nextWindowStartedAtMs = nowMs;
      nextCount = 1;
    }

    if (nextCooldownUntilMs <= nowMs && nextCount >= _softBlockGuardThreshold) {
      nextCooldownUntilMs = nowMs + _softBlockGuardCooldown.inMilliseconds;
      nextWindowStartedAtMs = nowMs;
      nextCount = 0;
      if (_softBlockGuardLogCount < _maxSoftBlockGuardLogs) {
        _softBlockGuardLogCount += 1;
        _logger.log(
          'soft_guard activate key=$key guard=$guard cooldownMs=${_softBlockGuardCooldown.inMilliseconds}',
        );
      }
    }

    _softBlockGuardStates[key] = _SoftBlockGuardState(
      windowStartedAtMs: nextWindowStartedAtMs,
      blockCountInWindow: nextCount,
      cooldownUntilMs: nextCooldownUntilMs,
    );
    _trimSoftBlockGuardStates();
  }

  String _softBlockGuardKey(AdblockRequestContext request) {
    final explicitSignalKey = (request.adSignalKey ?? '').trim().toLowerCase();
    if (explicitSignalKey.isNotEmpty) {
      return explicitSignalKey;
    }
    final source = request.sourceUrl;
    if (source != null) {
      final sourceVideoId = _videoIdFromSourceUri(source);
      if (sourceVideoId.isNotEmpty) {
        return 'video:$sourceVideoId';
      }
      final sourcePath = source.path.toLowerCase();
      // Avoid sharing one broad guard key across different watch videos when
      // `v` is missing from sourceUrl. Fall back to request key in that case.
      if (sourcePath.startsWith('/watch')) {
        return 'request:${request.uri.host.toLowerCase()}${request.uri.path.toLowerCase()}';
      }
      if (source.host.isNotEmpty && sourcePath.isNotEmpty) {
        return 'source:${source.host.toLowerCase()}$sourcePath';
      }
    }
    return 'request:${request.uri.host.toLowerCase()}${request.uri.path.toLowerCase()}';
  }

  String _videoIdFromSourceUri(Uri uri) {
    final videoId = (uri.queryParameters['v'] ?? '').trim();
    if (videoId.isNotEmpty) {
      return videoId;
    }
    final segments = uri.pathSegments;
    final shortsIndex = segments.indexOf('shorts');
    if (shortsIndex >= 0 && segments.length > shortsIndex + 1) {
      return segments[shortsIndex + 1].trim();
    }
    return '';
  }

  void _trimSoftBlockGuardStates() {
    while (_softBlockGuardStates.length > _maxSoftBlockGuardStateEntries) {
      _softBlockGuardStates.remove(_softBlockGuardStates.keys.first);
    }
  }

  void _recordAdSignal(
    AdblockRequestContext request, {
    required String source,
  }) {
    if (!_enableAdSignalWindowGuard) {
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final key = _softBlockGuardKey(request);
    final existing = _adSignalStates.remove(key);
    final activeUntilCandidate = nowMs + _adSignalWindow.inMilliseconds;
    final activeUntilMs = existing == null
        ? activeUntilCandidate
        : activeUntilCandidate > existing.activeUntilMs
        ? activeUntilCandidate
        : existing.activeUntilMs;
    _adSignalStates[key] = _AdSignalState(
      activeUntilMs: activeUntilMs,
      lastSource: source,
    );
    _trimAdSignalStates();
    if (!_config.debugMode || _adSignalLogCount >= _maxAdSignalLogs) {
      return;
    }
    _adSignalLogCount += 1;
    _logger.log(
      'ad_signal set key=$key source=$source ttlMs=${activeUntilMs - nowMs}',
    );
  }

  bool _isAdSignalActive(AdblockRequestContext request) {
    if (!_enableAdSignalWindowGuard) {
      return request.adShowing;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final key = _softBlockGuardKey(request);
    final state = _adSignalStates.remove(key);
    if (state == null) {
      return false;
    }
    if (state.activeUntilMs <= nowMs) {
      return false;
    }
    _adSignalStates[key] = state;
    return true;
  }

  void _trimAdSignalStates() {
    while (_adSignalStates.length > _maxAdSignalStateEntries) {
      _adSignalStates.remove(_adSignalStates.keys.first);
    }
  }

  void _recordDecisionStats(AdblockDecision decision) {
    if (!_config.debugMode) {
      return;
    }
    _decisionStatsSampleCount += 1;
    if (decision.blocked) {
      _decisionStatsBlockedCount += 1;
    }
    final key = '${decision.blocked ? 'b' : 'a'}:${decision.reason}';
    _decisionReasonCounts.update(key, (value) => value + 1, ifAbsent: () => 1);
    if (_decisionStatsSampleCount < _decisionStatsLogInterval) {
      return;
    }
    final entries = _decisionReasonCounts.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    final topSummary = entries
        .take(6)
        .map((entry) => '${entry.key}=${entry.value}')
        .join(',');
    _logger.log(
      'decision_stats sample=$_decisionStatsSampleCount blocked=$_decisionStatsBlockedCount top=${topSummary.isEmpty ? 'none' : topSummary}',
    );
    _decisionReasonCounts.clear();
    _decisionStatsSampleCount = 0;
    _decisionStatsBlockedCount = 0;
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

  int _countQueryKeyHitsInRawQuery(
    String rawQuery,
    List<String> keys, {
    int maxHits = 999,
  }) {
    if (rawQuery.isEmpty || keys.isEmpty || maxHits <= 0) {
      return 0;
    }
    final normalizedQuery = '&${rawQuery.toLowerCase()}&';
    var hits = 0;
    for (final key in keys) {
      if (normalizedQuery.contains('&$key=') ||
          normalizedQuery.contains('&$key&')) {
        hits += 1;
        if (hits >= maxHits) {
          return hits;
        }
      }
    }
    return hits;
  }

  bool _containsAllQueryKeysInRawQuery(String rawQuery, List<String> keys) {
    if (rawQuery.isEmpty || keys.isEmpty) {
      return false;
    }
    final normalizedQuery = '&${rawQuery.toLowerCase()}&';
    for (final key in keys) {
      final normalizedKey = key.trim().toLowerCase();
      if (normalizedKey.isEmpty) {
        continue;
      }
      if (!(normalizedQuery.contains('&$normalizedKey=') ||
          normalizedQuery.contains('&$normalizedKey&'))) {
        return false;
      }
    }
    return true;
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

  bool _containsAdLikeQueryValue(String rawQuery) {
    if (rawQuery.isEmpty) {
      return false;
    }
    for (final segment in rawQuery.split('&')) {
      if (segment.isEmpty) {
        continue;
      }
      final separator = segment.indexOf('=');
      if (separator == -1) {
        continue;
      }
      final rawValue = segment.substring(separator + 1);
      final value = _safeDecodeQueryComponent(rawValue).toLowerCase();
      if (_isAdLikeQueryValue(value)) {
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
    if (_googleVideoHardAdQueryKeys.contains(key)) {
      return true;
    }
    if (key.startsWith('dclk_')) {
      return true;
    }
    if (key.startsWith('videoad') ||
        key.endsWith('adid') ||
        key.endsWith('adsid')) {
      return true;
    }
    return false;
  }

  bool _isAdLikeQueryValue(String value) {
    if (value.isEmpty) {
      return false;
    }
    for (final marker in _googleVideoAggressiveGuardValueTokens) {
      if (value.contains(marker)) {
        return true;
      }
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

  bool _containsQueryKeyWithAnyValue(
    String rawQuery, {
    required String key,
    required List<String> candidateValues,
  }) {
    if (rawQuery.isEmpty || candidateValues.isEmpty) {
      return false;
    }
    final normalizedKey = key.trim().toLowerCase();
    if (normalizedKey.isEmpty) {
      return false;
    }
    final normalizedValues = candidateValues
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (normalizedValues.isEmpty) {
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
      if (decodedKey != normalizedKey || separator == -1) {
        continue;
      }
      final rawValue = segment.substring(separator + 1);
      final decodedValue = _safeDecodeQueryComponent(rawValue).toLowerCase();
      if (normalizedValues.contains(decodedValue)) {
        return true;
      }
    }
    return false;
  }

  bool _containsQueryKeyValueContainingAllTokens(
    String rawQuery, {
    required String key,
    required List<String> tokens,
  }) {
    if (rawQuery.isEmpty || tokens.isEmpty) {
      return false;
    }
    final normalizedKey = key.trim().toLowerCase();
    if (normalizedKey.isEmpty) {
      return false;
    }
    final normalizedTokens = tokens
        .map((token) => token.trim().toLowerCase())
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    if (normalizedTokens.isEmpty) {
      return false;
    }

    for (final segment in rawQuery.split('&')) {
      if (segment.isEmpty) {
        continue;
      }
      final separator = segment.indexOf('=');
      if (separator == -1) {
        continue;
      }
      final rawKey = segment.substring(0, separator);
      final decodedKey = _safeDecodeQueryComponent(rawKey).toLowerCase();
      if (decodedKey != normalizedKey) {
        continue;
      }
      final rawValue = segment.substring(separator + 1);
      final decodedValue = _safeDecodeQueryComponent(rawValue).toLowerCase();
      var allFound = true;
      for (final token in normalizedTokens) {
        if (!decodedValue.contains(token)) {
          allFound = false;
          break;
        }
      }
      if (allFound) {
        return true;
      }
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

  void _logGoogleVideoAllowTrace(
    AdblockRequestContext request, {
    required String reason,
  }) {
    if (!_config.debugMode ||
        _googleVideoAllowTraceCount >= _maxGoogleVideoAllowTraceLogs) {
      return;
    }
    final uri = request.uri;
    if (!_isGoogleVideoPlaybackRequest(uri)) {
      return;
    }
    _googleVideoAllowTraceCount += 1;
    final sourceLabel = _sourceSummary(request.sourceUrl);
    _logger.log(
      'googlevideo allow reason=$reason type=${request.resourceType.toLowerCase()} host=${uri.host} path=${uri.path} queryKeys=${_queryKeysSummary(uri.query)} adShowing=${request.adShowing} source=$sourceLabel sw=${request.fromServiceWorker}',
    );
    final markerHints = _adLikeMarkerHints(uri.query);
    if (request.adShowing) {
      if (_googleVideoAdShowingMarkerLogCount >=
          _maxGoogleVideoAdShowingMarkerLogs) {
        return;
      }
      _googleVideoAdShowingMarkerLogCount += 1;
      _logger.log(
        _enableGoogleVideoFullQueryLogs
            ? 'googlevideo allow ad-showing reason=$reason source=$sourceLabel fullQuery=${uri.query.isEmpty ? 'none' : uri.query} markerHints=${markerHints.isEmpty ? 'none' : markerHints.join(',')}'
            : 'googlevideo allow ad-showing reason=$reason source=$sourceLabel markerHints=${markerHints.isEmpty ? 'none' : markerHints.join(',')}',
      );
      return;
    }

    if (reason != 'engine_allow' ||
        !_isYouTubeBrowseSurfaceSource(request.sourceUrl) ||
        _googleVideoPreAdMarkerLogCount >= _maxGoogleVideoPreAdMarkerLogs) {
      return;
    }
    _googleVideoPreAdMarkerLogCount += 1;
    _logger.log(
      _enableGoogleVideoFullQueryLogs
          ? 'googlevideo allow pre-ad reason=$reason source=$sourceLabel fullQuery=${uri.query.isEmpty ? 'none' : uri.query} markerHints=${markerHints.isEmpty ? 'none' : markerHints.join(',')}'
          : 'googlevideo allow pre-ad reason=$reason source=$sourceLabel markerHints=${markerHints.isEmpty ? 'none' : markerHints.join(',')}',
    );
  }

  String _sourceSummary(Uri? sourceUrl) {
    if (sourceUrl == null) {
      return 'none';
    }
    final host = sourceUrl.host.trim().toLowerCase();
    final path = sourceUrl.path.trim().isEmpty ? '/' : sourceUrl.path.trim();
    if (host.isEmpty) {
      return path;
    }
    return '$host$path';
  }

  List<String> _adLikeMarkerHints(String rawQuery, {int limit = 10}) {
    if (rawQuery.isEmpty) {
      return const <String>[];
    }
    final hints = <String>[];
    final seen = <String>{};
    for (final segment in rawQuery.split('&')) {
      if (segment.isEmpty) {
        continue;
      }
      final separator = segment.indexOf('=');
      final rawKey = separator == -1
          ? segment
          : segment.substring(0, separator);
      final key = _safeDecodeQueryComponent(rawKey).toLowerCase();
      if (key.isEmpty) {
        continue;
      }
      final rawValue = separator == -1 ? '' : segment.substring(separator + 1);
      final value = _safeDecodeQueryComponent(rawValue).toLowerCase();
      final keyAdLike =
          _isAdLikeQueryKey(key) ||
          _googleVideoAggressiveGuardQueryKeys.contains(key);
      final valueAdLike = _isAdLikeQueryValue(value);
      if (!keyAdLike && !valueAdLike) {
        continue;
      }
      final compactValue = value.isEmpty
          ? ''
          : '=(${_clipForLog(value, maxChars: 42)})';
      final hint = '$key$compactValue';
      if (!seen.add(hint)) {
        continue;
      }
      hints.add(hint);
      if (hints.length >= limit) {
        break;
      }
    }
    return hints;
  }

  String _clipForLog(String value, {required int maxChars}) {
    if (value.length <= maxChars) {
      return value;
    }
    return '${value.substring(0, maxChars)}...';
  }

  String _queryKeysSummary(String rawQuery, {int limit = 10}) {
    if (rawQuery.isEmpty) {
      return 'none';
    }
    final keys = <String>[];
    final seen = <String>{};
    var truncated = false;
    for (final segment in rawQuery.split('&')) {
      if (segment.isEmpty) {
        continue;
      }
      final separator = segment.indexOf('=');
      final rawKey = separator == -1
          ? segment
          : segment.substring(0, separator);
      final key = _safeDecodeQueryComponent(rawKey).toLowerCase();
      if (key.isEmpty || !seen.add(key)) {
        continue;
      }
      if (keys.length >= limit) {
        truncated = true;
        break;
      }
      keys.add(key);
    }
    if (keys.isEmpty) {
      return 'none';
    }
    if (truncated) {
      return '${keys.join(',')},+more';
    }
    return keys.join(',');
  }

  String _cacheKey(AdblockRequestContext request) {
    final sourceHost = request.sourceUrl?.host.toLowerCase() ?? 'none';
    final signalKey = (request.adSignalKey ?? '').trim().toLowerCase();
    return '${request.resourceType.toLowerCase()}|${request.uri.scheme.toLowerCase()}://${request.uri.host.toLowerCase()}${request.uri.path}?${request.uri.query}|$sourceHost|ad=${request.adShowing}|stall=${request.playbackStalled}|sig=${signalKey.isEmpty ? 'none' : signalKey}|sw=${request.fromServiceWorker}';
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
      redirectDataUrl: entry.redirectDataUrl,
      rewrittenUrl: entry.rewrittenUrl,
      fromCache: true,
    );
  }

  void _writeCache(String key, AdblockDecision decision) {
    _decisionCache.remove(key);
    _decisionCache[key] = _DecisionCacheEntry(
      blocked: decision.blocked,
      reason: decision.reason,
      matchedRule: decision.matchedRule,
      redirectDataUrl: decision.redirectDataUrl,
      rewrittenUrl: decision.rewrittenUrl,
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
    required this.redirectDataUrl,
    required this.rewrittenUrl,
    required this.expiresAtMs,
  });

  final bool blocked;
  final String reason;
  final String? matchedRule;
  final String? redirectDataUrl;
  final String? rewrittenUrl;
  final int expiresAtMs;
}

class _SoftBlockGuardState {
  const _SoftBlockGuardState({
    required this.windowStartedAtMs,
    required this.blockCountInWindow,
    required this.cooldownUntilMs,
  });

  final int windowStartedAtMs;
  final int blockCountInWindow;
  final int cooldownUntilMs;
}

class _AdSignalState {
  const _AdSignalState({required this.activeUntilMs, required this.lastSource});

  final int activeUntilMs;
  final String lastSource;
}
