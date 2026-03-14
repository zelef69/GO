import 'dart:async';
import 'dart:collection';

import '../../domain_lock/domain_policy_service.dart';
import '../crowd/storage/learned_signature_repository.dart';
import '../intercept/request_interceptor.dart';
import '../youtube_ad_request_matcher.dart';
import 'adblock_config.dart';
import 'adblock_debug_logger.dart';
import 'adblock_metrics.dart';
import 'engine_request_policy_cache.dart';
import 'engine_request_policy_query_utils.dart';
import 'engine_request_policy_state.dart';
import 'request_runtime_models.dart';
import 'types.dart';

class EngineRequestPolicy {
  EngineRequestPolicy({
    required DomainPolicyService domainPolicyService,
    required AdblockDebugLogger logger,
    required AdblockMetricsCollector metrics,
    LearnedSignatureRepository? learnedSignatureRepository,
    RequestInterceptor requestInterceptor = const RequestInterceptor(),
  }) : _domainPolicyService = domainPolicyService,
       _logger = logger,
       _metrics = metrics,
       _learnedSignatureRepository = learnedSignatureRepository,
       _requestInterceptor = requestInterceptor;

  static const int _decisionCacheLimit = 2048;
  static const Duration _decisionCacheTtl = Duration(seconds: 25);
  static const int _maxGoogleVideoAllowTraceLogs = 240;
  static const int _maxGoogleVideoAdShowingMarkerLogs = 120;
  static const int _maxGoogleVideoPreAdMarkerLogs = 80;
  static const bool _enableGoogleVideoFullQueryLogs = false;
  static const bool _enableAdShowingGuardedGoogleVideoBlock = true;
  static const bool _enableGoogleVideoAdWindowStrictBlock = false;
  static const bool _enableGoogleVideoBrowsePrefetchGuard = true;
  static const bool _enablePageAdInteractionGuard = true;
  static const bool _enableAdSignalWindowGuard = true;
  static const bool _enableAdWindowEscalationGuard = true;
  static const bool _enableGoogleVideoOverblockFailOpenGuard = true;
  static const bool _enablePostBurstRecoveryBackoff = true;
  static const int _maxSoftBlockGuardLogs = 80;
  static const int _maxSoftLeakedRecoveryLogs = 80;
  static const int _maxPageAdStrongMarkerLogs = 120;
  static const int _maxGoogleVideoAdWindowFullQueryLogs = 60;
  static const int _maxAdWindowEscalationLogs = 80;
  static const int _maxPostBurstBackoffLogs = 80;
  static const Duration _softBlockGuardWindow = Duration(seconds: 4);
  static const int _softBlockGuardThreshold = 6;
  static const Duration _softBlockGuardCooldown = Duration(seconds: 8);
  static const int _maxSoftBlockGuardStateEntries = 240;
  static const Duration _softLeakedRecoveryWindow = Duration(seconds: 5);
  static const int _softLeakedRecoveryThreshold = 4;
  static const Duration _softLeakedRecoveryDuration = Duration(seconds: 4);
  static const int _maxSoftLeakedRecoveryStates = 240;
  static const Duration _adSignalWindow = Duration(seconds: 12);
  static const int _maxAdSignalStateEntries = 320;
  static const Duration _adWindowEscalationWindow = Duration(seconds: 3);
  static const int _adWindowEscalationAllowThreshold = 1;
  static const Duration _adWindowEscalationBlockFor = Duration(seconds: 3);
  static const int _maxAdWindowEscalationStates = 280;
  static const Duration _googleVideoOverblockWindow = Duration(seconds: 10);
  static const int _googleVideoOverblockConsecutiveWindowThreshold = 2;
  static const Duration _googleVideoOverblockFailOpenDuration = Duration(
    seconds: 25,
  );
  static const int _maxGoogleVideoOverblockStates = 280;
  static const int _maxGoogleVideoOverblockLogs = 120;
  static const Duration _postBurstWindow = Duration(seconds: 4);
  static const int _postBurstThreshold = 12;
  static const Duration _postBurstRecoveryDuration = Duration(seconds: 3);
  static const int _maxPostBurstStates = 280;
  static const int _maxAdSignalLogs = 80;
  static const int _maxSuspiciousAllowLogs = 220;
  static const int _decisionStatsLogInterval = 180;
  static const Duration _interceptProbeWindow = Duration(seconds: 10);
  static const int _maxInterceptProbeLogs = 120;
  static const int _maxDecisionDetailLogs = 700;
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
    'ad_cpn',
    'dur',
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
  final RequestInterceptor _requestInterceptor;
  final EngineRequestDecisionCache _decisionCache = EngineRequestDecisionCache(
    limit: _decisionCacheLimit,
    ttl: _decisionCacheTtl,
  );
  final EngineRequestQueryUtils _queryUtils = const EngineRequestQueryUtils(
    hardAdQueryKeys: _googleVideoHardAdQueryKeys,
    aggressiveGuardQueryKeys: _googleVideoAggressiveGuardQueryKeys,
    aggressiveGuardValueTokens: _googleVideoAggressiveGuardValueTokens,
  );
  final LinkedHashMap<String, SoftBlockGuardState> _softBlockGuardStates =
      LinkedHashMap<String, SoftBlockGuardState>();
  final LinkedHashMap<String, SoftLeakedRecoveryState>
  _softLeakedRecoveryStates = LinkedHashMap<String, SoftLeakedRecoveryState>();
  final LinkedHashMap<String, AdSignalState> _adSignalStates =
      LinkedHashMap<String, AdSignalState>();
  final LinkedHashMap<String, AdWindowEscalationState>
  _adWindowEscalationStates = LinkedHashMap<String, AdWindowEscalationState>();
  final LinkedHashMap<String, GoogleVideoOverblockState>
  _googleVideoOverblockStates =
      LinkedHashMap<String, GoogleVideoOverblockState>();
  final LinkedHashMap<String, PostBurstRecoveryState> _postBurstStates =
      LinkedHashMap<String, PostBurstRecoveryState>();
  final Map<String, int> _decisionReasonCounts = <String, int>{};
  int _googleVideoAllowTraceCount = 0;
  int _googleVideoAdShowingMarkerLogCount = 0;
  int _googleVideoPreAdMarkerLogCount = 0;
  int _googleVideoAdWindowFullQueryLogCount = 0;
  int _softBlockGuardLogCount = 0;
  int _softLeakedRecoveryLogCount = 0;
  int _pageAdStrongMarkerLogCount = 0;
  int _adSignalLogCount = 0;
  int _suspiciousAllowLogCount = 0;
  int _adWindowEscalationLogCount = 0;
  int _googleVideoOverblockLogCount = 0;
  int _postBurstBackoffLogCount = 0;
  int _decisionStatsSampleCount = 0;
  int _decisionStatsBlockedCount = 0;
  int _interceptProbeWindowStartMs = 0;
  int _interceptProbeLogCount = 0;
  int _interceptProbeRequestCount = 0;
  int _interceptProbeBlockedCount = 0;
  int _interceptProbeServiceWorkerCount = 0;
  int _interceptProbeAdShowingCount = 0;
  int _interceptProbeStalledCount = 0;
  int _interceptProbeCacheHitCount = 0;
  int _interceptProbeMediaRequestCount = 0;
  int _interceptProbeMediaBlockedCount = 0;
  int _interceptProbeFailOpenAllowCount = 0;
  int _decisionDetailLogCount = 0;
  final Map<String, int> _interceptProbeTypeCounts = <String, int>{};
  final Map<String, int> _interceptProbeReasonCounts = <String, int>{};
  AdblockConfig _config = AdblockConfig.defaults(
    enabled: true,
    debugMode: false,
  );
  bool _firstPartyHeuristicProfileEnabled = false;
  AdblockRuntimeEngine? _engine;

  void setConfig(AdblockConfig config) {
    _config = config;
    _decisionCache.clear();
    _softBlockGuardStates.clear();
    _softLeakedRecoveryStates.clear();
    _adSignalStates.clear();
    _adWindowEscalationStates.clear();
    _googleVideoOverblockStates.clear();
    _postBurstStates.clear();
    _decisionReasonCounts.clear();
    _googleVideoAllowTraceCount = 0;
    _googleVideoAdShowingMarkerLogCount = 0;
    _googleVideoPreAdMarkerLogCount = 0;
    _googleVideoAdWindowFullQueryLogCount = 0;
    _softBlockGuardLogCount = 0;
    _softLeakedRecoveryLogCount = 0;
    _pageAdStrongMarkerLogCount = 0;
    _adSignalLogCount = 0;
    _suspiciousAllowLogCount = 0;
    _adWindowEscalationLogCount = 0;
    _googleVideoOverblockLogCount = 0;
    _postBurstBackoffLogCount = 0;
    _decisionStatsSampleCount = 0;
    _decisionStatsBlockedCount = 0;
    _interceptProbeWindowStartMs = 0;
    _interceptProbeLogCount = 0;
    _interceptProbeRequestCount = 0;
    _interceptProbeBlockedCount = 0;
    _interceptProbeServiceWorkerCount = 0;
    _interceptProbeAdShowingCount = 0;
    _interceptProbeStalledCount = 0;
    _interceptProbeCacheHitCount = 0;
    _interceptProbeMediaRequestCount = 0;
    _interceptProbeMediaBlockedCount = 0;
    _interceptProbeFailOpenAllowCount = 0;
    _decisionDetailLogCount = 0;
    _interceptProbeTypeCounts.clear();
    _interceptProbeReasonCounts.clear();
  }

  void setEngine(AdblockRuntimeEngine engine) {
    _engine = engine;
  }

  void setFirstPartyHeuristicProfile(bool enabled) {
    if (_firstPartyHeuristicProfileEnabled == enabled) {
      return;
    }
    _firstPartyHeuristicProfileEnabled = enabled;
    _decisionCache.clear();
    _softBlockGuardStates.clear();
    _softLeakedRecoveryStates.clear();
    _adSignalStates.clear();
    _googleVideoOverblockStates.clear();
    _logger.log('first_party_heuristic_profile enabled=$enabled');
  }

  void clearCache() {
    _decisionCache.clear();
    _softBlockGuardStates.clear();
    _softLeakedRecoveryStates.clear();
    _adSignalStates.clear();
    _adWindowEscalationStates.clear();
    _googleVideoOverblockStates.clear();
    _postBurstStates.clear();
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
    _recordGoogleVideoOverblockProbe(request, result);
    _recordInterceptProbe(request, result);
    _recordDecisionStats(result);
    _logDecisionDetail(request, result, elapsedMs);
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

    // Direct guard: if googlevideo playback carries clear ad markers,
    // block immediately even when adShowing signal is not currently active.
    if (_shouldDirectlyBlockGoogleVideoAdMarkedRequest(
      request,
      normalizedType,
    )) {
      _recordAdSignal(request, source: 'googlevideo_direct_marker');
      return _finalizeBlockedDecision(
        request,
        AdblockDecision(
          blocked: true,
          reason: 'googlevideo_ad_query_direct',
          matchedRule: uri.toString(),
        ),
      );
    }

    // Recovery guard: when player is in a stalled state, temporarily fail-open
    // googlevideo streams so playback can recover from readyState=0 loops.
    if (!request.adShowing &&
        request.playbackStalled &&
        _isGoogleVideoPlaybackRequest(uri) &&
        (normalizedType == 'media' || normalizedType == 'xmlhttprequest')) {
      _logGoogleVideoAllowTrace(request, reason: 'playback_stall_backoff');
      return const AdblockDecision(
        blocked: false,
        reason: 'playback_stall_backoff',
      );
    }

    if (_shouldApplyPostBurstRecoveryBackoff(request, normalizedType)) {
      _logGoogleVideoAllowTrace(request, reason: 'post_burst_recovery_backoff');
      return const AdblockDecision(
        blocked: false,
        reason: 'post_burst_recovery_backoff',
      );
    }

    if (_shouldFailOpenGoogleVideoAfterOverblock(request, normalizedType)) {
      _logGoogleVideoAllowTrace(request, reason: 'overblock_fail_open');
      return const AdblockDecision(
        blocked: false,
        reason: 'overblock_fail_open',
      );
    }

    if (_shouldStrictBlockGoogleVideoDuringAdWindow(request, normalizedType)) {
      return _finalizeBlockedDecision(
        request,
        AdblockDecision(
          blocked: true,
          reason: 'googlevideo_ad_showing_strict',
          matchedRule: uri.toString(),
        ),
      );
    }

    if (_shouldEscalateBlockGoogleVideoInAdWindow(request, normalizedType)) {
      return _finalizeBlockedDecision(
        request,
        AdblockDecision(
          blocked: true,
          reason: 'googlevideo_ad_window_escalation',
          matchedRule: uri.toString(),
        ),
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
      final leakedSoftPattern = _isLeakedSoftGuardGoogleVideoRequest(
        request,
        normalizedType,
      );
      if (_shouldApplySoftLeakedRecoveryBackoff(
        request,
        normalizedType,
        leakedSoftMarker: leakedSoftPattern,
      )) {
        _logGoogleVideoAllowTrace(
          request,
          reason: 'soft_leaked_recovery_backoff',
        );
      } else if (!_shouldEnforceStrictAdShowingBlock(request, normalizedType) &&
          _shouldBypassSoftBlockWithCooldown(request, guard: 'ad_showing')) {
        _logGoogleVideoAllowTrace(
          request,
          reason: 'soft_guard_cooldown_ad_showing',
        );
      } else {
        _recordSoftBlock(request, guard: 'ad_showing');
        if (leakedSoftPattern) {
          _recordSoftLeakedBlock(request);
        }
        return _finalizeBlockedDecision(
          request,
          AdblockDecision(
            blocked: true,
            reason: leakedSoftPattern
                ? 'googlevideo_ad_query_soft_leaked'
                : 'googlevideo_ad_query_soft',
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
    final bypassAllowCache = _shouldBypassAllowCache(request, normalizedType);
    final cached = _readCache(decisionCacheKey);
    if (cached != null) {
      if (bypassAllowCache && !cached.blocked) {
        // Keep ad-window decisions fresh: never replay cached allow for
        // ad-showing googlevideo traffic.
      } else {
        if (!cached.blocked) {
          _recordAdWindowEscalationCandidate(request, cached, normalizedType);
          _logGoogleVideoAllowTrace(request, reason: 'cache_${cached.reason}');
        }
        return cached;
      }
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

    RequestDecision engineResult = RequestDecision.allow();
    try {
      final normalizeStopwatch = Stopwatch()..start();
      final normalizedContext = request.toRequestContext(_requestInterceptor);
      normalizeStopwatch.stop();
      final observer = engine is RequestNormalizationObserver
          ? engine as RequestNormalizationObserver
          : null;
      observer?.recordRequestNormalizationMicros(
        normalizeStopwatch.elapsedMicroseconds,
      );
      engineResult = await engine.evaluateRequest(normalizedContext);
    } catch (_) {
      _logger.log(
        'engine evaluate failed uri=${uri.host}${uri.path} type=${request.resourceType}',
      );
      engineResult = RequestDecision.allow(reason: 'engine_error_allow');
    }

    final decision = _mapEngineDecision(engineResult, uri);
    if (!decision.blocked) {
      _recordAdWindowEscalationCandidate(request, decision, normalizedType);
      _logGoogleVideoAllowTrace(
        request,
        reason: decision.reason == 'allowed' ? 'engine_allow' : decision.reason,
      );
      _logSuspiciousAllow(request, decision, normalizedType);
    } else {
      _recordCrowdDecision(request, decision);
    }
    if (!(bypassAllowCache && !decision.blocked)) {
      _writeCache(decisionCacheKey, decision);
    }
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
    _recordPostBurstBlockedDecision(request, decision);
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

  bool _shouldEscalateBlockGoogleVideoInAdWindow(
    AdblockRequestContext request,
    String normalizedType,
  ) {
    if (!_enableAdWindowEscalationGuard ||
        !_isAdWindowEscalationType(normalizedType)) {
      return false;
    }
    if (!_isGoogleVideoPlaybackRequest(request.uri)) {
      return false;
    }
    if (!_shouldConsiderAdWindowEscalation(request)) {
      return false;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final key = _adWindowEscalationKey(request);
    final state = _adWindowEscalationStates.remove(key);
    if (state == null) {
      return false;
    }
    if (state.blockUntilMs <= nowMs) {
      if (state.windowStartedAtMs + _adWindowEscalationWindow.inMilliseconds <=
          nowMs) {
        return false;
      }
      _adWindowEscalationStates[key] = state;
      return false;
    }
    _adWindowEscalationStates[key] = state;
    if (_adWindowEscalationLogCount < _maxAdWindowEscalationLogs) {
      _adWindowEscalationLogCount += 1;
      _logger.log(
        'ad_window escalation_block key=$key host=${request.uri.host} path=${request.uri.path} blockLeftMs=${state.blockUntilMs - nowMs}',
      );
    }
    return true;
  }

  void _recordAdWindowEscalationCandidate(
    AdblockRequestContext request,
    AdblockDecision decision,
    String normalizedType,
  ) {
    if (!_enableAdWindowEscalationGuard ||
        decision.reason != 'allowed' ||
        !_isAdWindowEscalationType(normalizedType)) {
      return;
    }
    if (!_isGoogleVideoPlaybackRequest(request.uri)) {
      return;
    }
    if (!_shouldConsiderAdWindowEscalation(request)) {
      return;
    }
    final rawQuery = request.uri.query;
    if (rawQuery.isEmpty) {
      return;
    }
    final hasExplicitAdMarkers =
        _containsAnyQueryKeyInRawQuery(rawQuery, _googleVideoHardAdQueryKeys) ||
        _containsAnyQueryKeyInRawQuery(rawQuery, _googleVideoSoftAdQueryKeys) ||
        _containsAdLikeQueryKey(rawQuery) ||
        _containsAdLikeQueryValue(rawQuery);
    if (hasExplicitAdMarkers) {
      return;
    }
    final looksPrimaryContent =
        _containsAllQueryKeysInRawQuery(
          rawQuery,
          _primaryPlaybackRequiredQueryKeys,
        ) &&
        _containsAnyQueryKeyInRawQuery(rawQuery, const <String>[
          'mime',
          'clen',
        ]);
    if (looksPrimaryContent) {
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final key = _adWindowEscalationKey(request);
    final existing = _adWindowEscalationStates.remove(key);
    var windowStartedAtMs = nowMs;
    var allowCountInWindow = 1;
    var blockUntilMs = 0;
    if (existing != null &&
        existing.windowStartedAtMs + _adWindowEscalationWindow.inMilliseconds >
            nowMs) {
      windowStartedAtMs = existing.windowStartedAtMs;
      allowCountInWindow = existing.allowCountInWindow + 1;
      blockUntilMs = existing.blockUntilMs > nowMs ? existing.blockUntilMs : 0;
    }
    if (blockUntilMs <= nowMs &&
        allowCountInWindow >= _adWindowEscalationAllowThreshold) {
      blockUntilMs = nowMs + _adWindowEscalationBlockFor.inMilliseconds;
      allowCountInWindow = 0;
      if (_adWindowEscalationLogCount < _maxAdWindowEscalationLogs) {
        _adWindowEscalationLogCount += 1;
        _logger.log(
          'ad_window escalation_arm key=$key host=${request.uri.host} path=${request.uri.path} blockMs=${_adWindowEscalationBlockFor.inMilliseconds}',
        );
      }
    }
    _adWindowEscalationStates[key] = AdWindowEscalationState(
      windowStartedAtMs: windowStartedAtMs,
      allowCountInWindow: allowCountInWindow,
      blockUntilMs: blockUntilMs,
    );
    _trimAdWindowEscalationStates();
  }

  bool _shouldConsiderAdWindowEscalation(AdblockRequestContext request) {
    final adSignalActive = request.adShowing || _isAdSignalActive(request);
    if (!_isWatchSurfaceContext(request)) {
      return false;
    }
    if (adSignalActive) {
      return true;
    }
    final rawQuery = request.uri.query;
    if (rawQuery.isEmpty) {
      return false;
    }
    if (_hasStrongPrimaryPlaybackSignature(rawQuery)) {
      return false;
    }
    if (_hasGoogleVideoConservativeSoftAdMarkers(rawQuery)) {
      return true;
    }
    if (_containsAdLikeQueryKey(rawQuery) ||
        _containsAdLikeQueryValue(rawQuery)) {
      return true;
    }
    return _matchesLeakedGoogleVideoAdPattern(rawQuery);
  }

  String _adWindowEscalationKey(AdblockRequestContext request) {
    final signalKey = _softBlockGuardKey(request);
    return '$signalKey|${request.uri.host.toLowerCase()}${request.uri.path.toLowerCase()}';
  }

  void _trimAdWindowEscalationStates() {
    while (_adWindowEscalationStates.length > _maxAdWindowEscalationStates) {
      _adWindowEscalationStates.remove(_adWindowEscalationStates.keys.first);
    }
  }

  void _recordPostBurstBlockedDecision(
    AdblockRequestContext request,
    AdblockDecision decision,
  ) {
    if (!_enablePostBurstRecoveryBackoff ||
        !_shouldCountTowardPostBurst(decision.reason)) {
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final key = _softBlockGuardKey(request);
    final existing = _postBurstStates.remove(key);
    var windowStartedAtMs = nowMs;
    var blockedCountInWindow = 1;
    var recoveryUntilMs = 0;
    if (existing != null &&
        existing.windowStartedAtMs + _postBurstWindow.inMilliseconds > nowMs) {
      windowStartedAtMs = existing.windowStartedAtMs;
      blockedCountInWindow = existing.blockedCountInWindow + 1;
      recoveryUntilMs = existing.recoveryUntilMs > nowMs
          ? existing.recoveryUntilMs
          : 0;
    }
    if (recoveryUntilMs <= nowMs &&
        blockedCountInWindow >= _postBurstThreshold) {
      recoveryUntilMs = nowMs + _postBurstRecoveryDuration.inMilliseconds;
      blockedCountInWindow = 0;
      if (_postBurstBackoffLogCount < _maxPostBurstBackoffLogs) {
        _postBurstBackoffLogCount += 1;
        _logger.log(
          'post_burst recovery_arm key=$key cooldownMs=${_postBurstRecoveryDuration.inMilliseconds}',
        );
      }
    }
    _postBurstStates[key] = PostBurstRecoveryState(
      windowStartedAtMs: windowStartedAtMs,
      blockedCountInWindow: blockedCountInWindow,
      recoveryUntilMs: recoveryUntilMs,
    );
    _trimPostBurstStates();
  }

  bool _shouldApplyPostBurstRecoveryBackoff(
    AdblockRequestContext request,
    String normalizedType,
  ) {
    if (!_enablePostBurstRecoveryBackoff ||
        !_isGoogleVideoPlaybackRequest(request.uri) ||
        !_isWatchSurfaceContext(request) ||
        (normalizedType != 'media' && normalizedType != 'xmlhttprequest')) {
      return false;
    }
    if (request.adShowing) {
      return false;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final key = _softBlockGuardKey(request);
    final state = _postBurstStates.remove(key);
    if (state == null) {
      return false;
    }
    if (state.recoveryUntilMs <= nowMs) {
      return false;
    }
    _postBurstStates[key] = state;
    if (_postBurstBackoffLogCount < _maxPostBurstBackoffLogs) {
      _postBurstBackoffLogCount += 1;
      _logger.log(
        'post_burst recovery_bypass key=$key cooldownLeftMs=${state.recoveryUntilMs - nowMs}',
      );
    }
    return true;
  }

  bool _shouldFailOpenGoogleVideoAfterOverblock(
    AdblockRequestContext request,
    String normalizedType,
  ) {
    if (!_enableGoogleVideoOverblockFailOpenGuard ||
        !_isGoogleVideoOverblockCandidateRequest(request, normalizedType)) {
      return false;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final key = _softBlockGuardKey(request);
    final existing = _googleVideoOverblockStates.remove(key);
    if (existing == null) {
      return false;
    }
    final updated = _advanceGoogleVideoOverblockWindow(
      key: key,
      state: existing,
      nowMs: nowMs,
    );
    _googleVideoOverblockStates[key] = updated;
    _trimGoogleVideoOverblockStates();
    if (updated.failOpenUntilMs <= nowMs) {
      return false;
    }
    if (_googleVideoOverblockLogCount < _maxGoogleVideoOverblockLogs) {
      _googleVideoOverblockLogCount += 1;
      _logger.log(
        'overblock fail_open_apply key=$key leftMs=${updated.failOpenUntilMs - nowMs} type=$normalizedType',
      );
    }
    return true;
  }

  void _recordGoogleVideoOverblockProbe(
    AdblockRequestContext request,
    AdblockDecision decision,
  ) {
    final normalizedType = request.resourceType.trim().toLowerCase();
    if (!_enableGoogleVideoOverblockFailOpenGuard ||
        !_isGoogleVideoOverblockCandidateRequest(request, normalizedType)) {
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final key = _softBlockGuardKey(request);
    final existing =
        _googleVideoOverblockStates.remove(key) ??
        GoogleVideoOverblockState(
          windowStartedAtMs: nowMs,
          requestCountInWindow: 0,
          blockedCountInWindow: 0,
          consecutiveFullBlockWindows: 0,
          failOpenUntilMs: 0,
        );
    final refreshed = _advanceGoogleVideoOverblockWindow(
      key: key,
      state: existing,
      nowMs: nowMs,
    );
    if (decision.reason == 'overblock_fail_open') {
      _googleVideoOverblockStates[key] = refreshed;
      _trimGoogleVideoOverblockStates();
      return;
    }
    var consecutiveFullBlockWindows = refreshed.consecutiveFullBlockWindows;
    if (!decision.blocked && refreshed.failOpenUntilMs <= nowMs) {
      consecutiveFullBlockWindows = 0;
    }
    _googleVideoOverblockStates[key] = GoogleVideoOverblockState(
      windowStartedAtMs: refreshed.windowStartedAtMs,
      requestCountInWindow: refreshed.requestCountInWindow + 1,
      blockedCountInWindow:
          refreshed.blockedCountInWindow + (decision.blocked ? 1 : 0),
      consecutiveFullBlockWindows: consecutiveFullBlockWindows,
      failOpenUntilMs: refreshed.failOpenUntilMs > nowMs
          ? refreshed.failOpenUntilMs
          : 0,
    );
    _trimGoogleVideoOverblockStates();
  }

  GoogleVideoOverblockState _advanceGoogleVideoOverblockWindow({
    required String key,
    required GoogleVideoOverblockState state,
    required int nowMs,
  }) {
    if (nowMs - state.windowStartedAtMs <
        _googleVideoOverblockWindow.inMilliseconds) {
      return state;
    }

    var consecutiveFullBlockWindows = state.consecutiveFullBlockWindows;
    final hadRequests = state.requestCountInWindow > 0;
    final isFullyBlockedWindow =
        hadRequests && state.blockedCountInWindow >= state.requestCountInWindow;
    if (isFullyBlockedWindow) {
      consecutiveFullBlockWindows += 1;
      if (_googleVideoOverblockLogCount < _maxGoogleVideoOverblockLogs) {
        _googleVideoOverblockLogCount += 1;
        _logger.log(
          'overblock window_full key=$key req=${state.requestCountInWindow} blocked=${state.blockedCountInWindow} streak=$consecutiveFullBlockWindows',
        );
      }
    } else if (hadRequests && state.failOpenUntilMs <= nowMs) {
      consecutiveFullBlockWindows = 0;
    }

    var failOpenUntilMs = state.failOpenUntilMs;
    if (failOpenUntilMs <= nowMs &&
        consecutiveFullBlockWindows >=
            _googleVideoOverblockConsecutiveWindowThreshold) {
      failOpenUntilMs =
          nowMs + _googleVideoOverblockFailOpenDuration.inMilliseconds;
      consecutiveFullBlockWindows = 0;
      if (_googleVideoOverblockLogCount < _maxGoogleVideoOverblockLogs) {
        _googleVideoOverblockLogCount += 1;
        _logger.log(
          'overblock fail_open_arm key=$key durationMs=${_googleVideoOverblockFailOpenDuration.inMilliseconds}',
        );
      }
    }

    return GoogleVideoOverblockState(
      windowStartedAtMs: nowMs,
      requestCountInWindow: 0,
      blockedCountInWindow: 0,
      consecutiveFullBlockWindows: consecutiveFullBlockWindows,
      failOpenUntilMs: failOpenUntilMs,
    );
  }

  bool _isGoogleVideoOverblockCandidateRequest(
    AdblockRequestContext request,
    String normalizedType,
  ) {
    if (!_isGoogleVideoOverblockTrackedType(normalizedType) ||
        !request.adShowing) {
      return false;
    }
    if (!_isGoogleVideoPlaybackRequest(request.uri)) {
      return false;
    }
    return _isWatchSurfaceContext(request);
  }

  bool _isGoogleVideoOverblockTrackedType(String normalizedType) {
    return normalizedType == 'media' || normalizedType == 'xmlhttprequest';
  }

  bool _shouldCountTowardPostBurst(String reason) {
    if (reason == 'learned_signature' ||
        reason == 'engine_match' ||
        reason == 'third_party_tracker') {
      return true;
    }
    if (reason.startsWith('pagead_') || reason.startsWith('googlevideo_')) {
      return true;
    }
    return false;
  }

  void _trimPostBurstStates() {
    while (_postBurstStates.length > _maxPostBurstStates) {
      _postBurstStates.remove(_postBurstStates.keys.first);
    }
  }

  void _trimGoogleVideoOverblockStates() {
    while (_googleVideoOverblockStates.length >
        _maxGoogleVideoOverblockStates) {
      _googleVideoOverblockStates.remove(
        _googleVideoOverblockStates.keys.first,
      );
    }
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
    if (!_hasStrongPrimaryPlaybackSignature(rawQuery)) {
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

  bool _hasStrongPrimaryPlaybackSignature(String rawQuery) {
    if (rawQuery.isEmpty) {
      return false;
    }
    final contentSignalHits = _countQueryKeyHitsInRawQuery(
      rawQuery,
      _primaryPlaybackContentSignalKeys,
      maxHits: 6,
    );
    if (contentSignalHits < 2) {
      return false;
    }
    final hasMimeAndLength =
        _containsAnyQueryKeyInRawQuery(rawQuery, const <String>['mime']) &&
        _containsAnyQueryKeyInRawQuery(rawQuery, const <String>['clen']);
    if (hasMimeAndLength) {
      return true;
    }
    return _containsAnyQueryKeyInRawQuery(rawQuery, const <String>['dur']) &&
        _containsAnyQueryKeyInRawQuery(rawQuery, const <String>['clen']);
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
    final hasKnownAdLabel = _containsQueryKeyWithAnyValue(
      rawQuery,
      key: 'label',
      candidateValues: _googleVideoAdLabelValues,
    );
    final hasAdMt = _containsAnyQueryKeyInRawQuery(rawQuery, <String>['ad_mt']);
    final hasAdTelemetryPack = _containsAnyQueryKeyInRawQuery(
      rawQuery,
      <String>['acvw', 'ai', 'cid', 'sigh', 'ad_cpn'],
    );
    // Conservative upgrade: if pagead interaction has explicit ad lifecycle
    // markers, block even when adShowing/watch-surface signal is missing.
    final hasStrongAdMarkers =
        (hasKnownAdLabel && hasAdMt) ||
        (hasKnownAdLabel && hasAdTelemetryPack) ||
        _containsAllQueryKeysInRawQuery(rawQuery, <String>['label', 'ad_mt']) ||
        _containsAllQueryKeysInRawQuery(rawQuery, <String>['ad_mt', 'acvw']) ||
        _containsAllQueryKeysInRawQuery(rawQuery, <String>[
          'label',
          'ad_mt',
          'dur',
        ]);
    if (hasStrongAdMarkers) {
      _logPageAdStrongMarker(request);
      return true;
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
    if (_isWatchSurfaceContext(request)) {
      return true;
    }
    return false;
  }

  void _logPageAdStrongMarker(AdblockRequestContext request) {
    if (!_config.debugMode ||
        _pageAdStrongMarkerLogCount >= _maxPageAdStrongMarkerLogs) {
      return;
    }
    _pageAdStrongMarkerLogCount += 1;
    final uri = request.uri;
    _logger.log(
      'pagead strong_marker host=${uri.host} path=${uri.path} queryKeys=${_queryKeysSummary(uri.query)} source=${_sourceSummary(request.sourceUrl)} adShowing=${request.adShowing}',
    );
  }

  bool _isGoogleVideoHardAdPlaybackRequest(Uri uri) {
    if (!_isGoogleVideoPlaybackRequest(uri)) {
      return false;
    }
    final rawQuery = uri.query;
    return _hasGoogleVideoHardAdMarkers(rawQuery);
  }

  bool _shouldDirectlyBlockGoogleVideoAdMarkedRequest(
    AdblockRequestContext request,
    String normalizedType,
  ) {
    if (request.adShowing) {
      return false;
    }
    if (normalizedType != 'media' &&
        normalizedType != 'xmlhttprequest' &&
        normalizedType != 'other') {
      return false;
    }
    if (!_isGoogleVideoPlaybackRequest(request.uri)) {
      return false;
    }
    final rawQuery = request.uri.query;
    if (rawQuery.isEmpty) {
      return false;
    }
    if (_hasStrongPrimaryPlaybackSignature(rawQuery) &&
        !_hasGoogleVideoHardAdMarkers(rawQuery)) {
      return false;
    }
    if (_hasGoogleVideoHardAdMarkers(rawQuery) ||
        _hasGoogleVideoConservativeSoftAdMarkers(rawQuery) ||
        _matchesLeakedGoogleVideoAdPattern(rawQuery)) {
      return true;
    }
    final hasAggressiveKeys = _containsAnyQueryKeyInRawQuery(
      rawQuery,
      _googleVideoAggressiveGuardQueryKeys,
    );
    if (!hasAggressiveKeys) {
      return false;
    }
    return _containsAdLikeQueryKey(rawQuery) ||
        _containsAdLikeQueryValue(rawQuery);
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
    // During playback stalls we still block high-confidence ad markers, but
    // avoid broad aggressive matching to reduce false positives.
    if (request.playbackStalled) {
      return _hasGoogleVideoHardAdMarkers(rawQuery) ||
          _hasGoogleVideoConservativeSoftAdMarkers(rawQuery) ||
          _matchesLeakedGoogleVideoAdPattern(rawQuery);
    }
    if (_hasGoogleVideoConservativeSoftAdMarkers(rawQuery)) {
      return true;
    }
    // request.adShowing already gates this guard; do not require additional
    // transient signal-state lookup which can miss real ad windows.
    return _hasGoogleVideoAggressiveSoftAdMarkers(rawQuery);
  }

  bool _shouldStrictBlockGoogleVideoDuringAdWindow(
    AdblockRequestContext request,
    String normalizedType,
  ) {
    if (!_enableGoogleVideoAdWindowStrictBlock) {
      return false;
    }
    if (!request.adShowing || request.playbackStalled) {
      return false;
    }
    if (!_isGoogleVideoPlaybackRequest(request.uri)) {
      return false;
    }
    if (!_isWatchSurfaceContext(request)) {
      return false;
    }
    if (normalizedType == 'media') {
      return true;
    }
    if (normalizedType == 'other') {
      return true;
    }
    return _shouldEnforceStrictAdShowingBlock(request, normalizedType);
  }

  bool _shouldEnforceStrictAdShowingBlock(
    AdblockRequestContext request,
    String normalizedType,
  ) {
    if (!request.adShowing || request.playbackStalled) {
      return false;
    }
    if (normalizedType != 'media' && normalizedType != 'xmlhttprequest') {
      return false;
    }
    if (!_isGoogleVideoPlaybackRequest(request.uri) ||
        !_isWatchSurfaceContext(request)) {
      return false;
    }
    final rawQuery = request.uri.query;
    if (rawQuery.isEmpty) {
      return false;
    }
    if (_hasStrongPrimaryPlaybackSignature(rawQuery)) {
      return false;
    }
    if (_hasGoogleVideoConservativeSoftAdMarkers(rawQuery) ||
        _matchesLeakedGoogleVideoAdPattern(rawQuery)) {
      return true;
    }
    if (_containsAnyQueryKeyInRawQuery(
      rawQuery,
      _googleVideoAggressiveGuardQueryKeys,
    )) {
      return true;
    }
    return _containsAdLikeQueryKey(rawQuery) ||
        _containsAdLikeQueryValue(rawQuery);
  }

  bool _isLeakedSoftGuardGoogleVideoRequest(
    AdblockRequestContext request,
    String normalizedType,
  ) {
    if (!request.adShowing) {
      return false;
    }
    if (normalizedType != 'media' && normalizedType != 'xmlhttprequest') {
      return false;
    }
    if (!_isGoogleVideoPlaybackRequest(request.uri)) {
      return false;
    }
    if (!_isWatchSurfaceContext(request)) {
      return false;
    }
    final rawQuery = request.uri.query;
    if (rawQuery.isEmpty) {
      return false;
    }
    return _matchesLeakedGoogleVideoAdPattern(rawQuery);
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
    if (_isWatchSurfaceContext(request)) {
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

  bool _isWatchSurfaceContext(AdblockRequestContext request) {
    if (_isYouTubeWatchSurfaceSource(request.sourceUrl)) {
      return true;
    }
    final signalKey = (request.adSignalKey ?? '').trim().toLowerCase();
    return signalKey.startsWith('video:');
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
    return path.startsWith('/results') ||
        path == '/feed' ||
        path.startsWith('/feed/');
  }

  bool _isYouTubeHost(String host) {
    return host == 'youtube.com' || host.endsWith('.youtube.com');
  }

  bool _isAdWindowEscalationType(String normalizedType) {
    return normalizedType == 'xmlhttprequest' || normalizedType == 'media';
  }

  bool _shouldBypassAllowCache(
    AdblockRequestContext request,
    String normalizedType,
  ) {
    if (!request.adShowing ||
        !_isGoogleVideoPlaybackRequest(request.uri) ||
        !_isAdWindowEscalationType(normalizedType)) {
      return false;
    }
    return true;
  }

  bool _shouldApplySoftLeakedRecoveryBackoff(
    AdblockRequestContext request,
    String normalizedType, {
    required bool leakedSoftMarker,
  }) {
    if (!leakedSoftMarker ||
        (normalizedType != 'media' && normalizedType != 'xmlhttprequest') ||
        !_isGoogleVideoPlaybackRequest(request.uri) ||
        !_isWatchSurfaceContext(request)) {
      return false;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final key = _softBlockGuardKey(request);
    final state = _softLeakedRecoveryStates.remove(key);
    if (state == null) {
      return false;
    }
    if (state.recoveryUntilMs <= nowMs) {
      return false;
    }
    _softLeakedRecoveryStates[key] = state;
    if (_softLeakedRecoveryLogCount < _maxSoftLeakedRecoveryLogs) {
      _softLeakedRecoveryLogCount += 1;
      _logger.log(
        'soft_leaked recovery_bypass key=$key cooldownLeftMs=${state.recoveryUntilMs - nowMs}',
      );
    }
    return true;
  }

  void _recordSoftLeakedBlock(AdblockRequestContext request) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final key = _softBlockGuardKey(request);
    final existing = _softLeakedRecoveryStates.remove(key);
    var windowStartedAtMs = nowMs;
    var blockedCountInWindow = 1;
    var recoveryUntilMs = 0;
    if (existing != null &&
        existing.windowStartedAtMs + _softLeakedRecoveryWindow.inMilliseconds >
            nowMs) {
      windowStartedAtMs = existing.windowStartedAtMs;
      blockedCountInWindow = existing.blockedCountInWindow + 1;
      recoveryUntilMs = existing.recoveryUntilMs > nowMs
          ? existing.recoveryUntilMs
          : 0;
    }
    if (recoveryUntilMs <= nowMs &&
        blockedCountInWindow >= _softLeakedRecoveryThreshold) {
      recoveryUntilMs = nowMs + _softLeakedRecoveryDuration.inMilliseconds;
      blockedCountInWindow = 0;
      if (_softLeakedRecoveryLogCount < _maxSoftLeakedRecoveryLogs) {
        _softLeakedRecoveryLogCount += 1;
        _logger.log(
          'soft_leaked recovery_arm key=$key cooldownMs=${_softLeakedRecoveryDuration.inMilliseconds}',
        );
      }
    }
    _softLeakedRecoveryStates[key] = SoftLeakedRecoveryState(
      windowStartedAtMs: windowStartedAtMs,
      blockedCountInWindow: blockedCountInWindow,
      recoveryUntilMs: recoveryUntilMs,
    );
    _trimSoftLeakedRecoveryStates();
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
      _softBlockGuardStates[key] = SoftBlockGuardState(
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

    _softBlockGuardStates[key] = SoftBlockGuardState(
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

  void _trimSoftLeakedRecoveryStates() {
    while (_softLeakedRecoveryStates.length > _maxSoftLeakedRecoveryStates) {
      _softLeakedRecoveryStates.remove(_softLeakedRecoveryStates.keys.first);
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
    _adSignalStates[key] = AdSignalState(
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

  void _logDecisionDetail(
    AdblockRequestContext request,
    AdblockDecision decision,
    int elapsedMs,
  ) {
    if (!_config.debugMode ||
        _decisionDetailLogCount >= _maxDecisionDetailLogs) {
      return;
    }
    _decisionDetailLogCount += 1;
    final uri = request.uri;
    final source = _sourceSummary(request.sourceUrl);
    final signalKey = (request.adSignalKey ?? 'none').trim().isEmpty
        ? 'none'
        : request.adSignalKey!.trim().toLowerCase();
    final watchContext = _isWatchSurfaceContext(request);
    _logger.log(
      'policy_decision รายละเอียด host=${uri.host} path=${uri.path} type=${request.resourceType.toLowerCase()} blocked=${decision.blocked} reason=${decision.reason} rule=${decision.matchedRule ?? 'none'} cache=${decision.fromCache} adShowing=${request.adShowing} stalled=${request.playbackStalled} watchContext=$watchContext sw=${request.fromServiceWorker} signalKey=$signalKey source=$source timeMs=$elapsedMs',
    );
  }

  AdblockDecision _mapEngineDecision(
    RequestDecision decision,
    Uri fallbackUri,
  ) {
    switch (decision.action) {
      case DecisionAction.allow:
        return AdblockDecision(
          blocked: false,
          reason: 'allowed',
          action: DecisionAction.allow,
          matchedRule: null,
          exceptionRule: decision.exceptionRule,
          fromCache: decision.fromCache,
          candidateCount: decision.candidateCount,
          evaluatedCount: decision.evaluatedCount,
        );
      case DecisionAction.block:
        return AdblockDecision(
          blocked: true,
          reason: 'engine_match',
          action: DecisionAction.block,
          matchedRule: decision.matchedRule ?? fallbackUri.toString(),
          exceptionRule: decision.exceptionRule,
          fromCache: decision.fromCache,
          candidateCount: decision.candidateCount,
          evaluatedCount: decision.evaluatedCount,
        );
      case DecisionAction.redirect:
        return AdblockDecision(
          blocked: true,
          reason: 'engine_redirect',
          action: DecisionAction.redirect,
          matchedRule: decision.matchedRule ?? fallbackUri.toString(),
          exceptionRule: decision.exceptionRule,
          redirectDataUrl: decision.redirectDataUrl,
          fromCache: decision.fromCache,
          candidateCount: decision.candidateCount,
          evaluatedCount: decision.evaluatedCount,
        );
      case DecisionAction.rewriteResponse:
        return AdblockDecision(
          blocked: false,
          reason: 'engine_rewrite',
          action: DecisionAction.rewriteResponse,
          matchedRule: decision.matchedRule,
          exceptionRule: decision.exceptionRule,
          rewrittenUrl: decision.rewrittenUrl,
          fromCache: decision.fromCache,
          candidateCount: decision.candidateCount,
          evaluatedCount: decision.evaluatedCount,
        );
    }
  }

  void _logSuspiciousAllow(
    AdblockRequestContext request,
    AdblockDecision decision,
    String normalizedType,
  ) {
    if (!_config.debugMode ||
        _suspiciousAllowLogCount >= _maxSuspiciousAllowLogs) {
      return;
    }
    final uri = request.uri;
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    final rawQuery = uri.query.toLowerCase();
    final looksLikeKnownAdHost =
        host.endsWith('.doubleclick.net') ||
        host.endsWith('.googlesyndication.com') ||
        host.endsWith('.googleadservices.com') ||
        host.endsWith('.taboola.com') ||
        host.endsWith('.outbrain.com') ||
        host.endsWith('.adsrvr.org');
    final looksLikeAdPath =
        path.contains('/ads') ||
        path.contains('/adserver') ||
        path.contains('/advert') ||
        path.contains('/sponsor');
    final looksLikeAdQuery =
        rawQuery.contains('adurl=') ||
        rawQuery.contains('ad_id=') ||
        rawQuery.contains('adid=') ||
        rawQuery.contains('ad_unit=') ||
        rawQuery.contains('adslot=') ||
        rawQuery.contains('advertiser=') ||
        rawQuery.contains('utm_medium=display');
    final suspicious =
        looksLikeKnownAdHost || looksLikeAdPath || looksLikeAdQuery;
    if (!suspicious) {
      return;
    }
    _suspiciousAllowLogCount += 1;
    _logger.log(
      'suspicious_allow host=$host path=$path type=$normalizedType reason=${decision.reason} adSignal=${request.adShowing} stalled=${request.playbackStalled} source=${_sourceSummary(request.sourceUrl)} queryKeys=${_queryKeysSummary(uri.query)}',
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
      _flushInterceptProbeWindow(nowMs);
    }

    _interceptProbeRequestCount += 1;
    if (decision.blocked) {
      _interceptProbeBlockedCount += 1;
    }
    if (request.fromServiceWorker) {
      _interceptProbeServiceWorkerCount += 1;
    }
    if (request.adShowing) {
      _interceptProbeAdShowingCount += 1;
    }
    if (request.playbackStalled) {
      _interceptProbeStalledCount += 1;
    }
    if (decision.fromCache) {
      _interceptProbeCacheHitCount += 1;
    }
    final typeKey = request.resourceType.trim().toLowerCase();
    if (_isGoogleVideoOverblockTrackedType(typeKey) &&
        _isGoogleVideoPlaybackRequest(request.uri)) {
      _interceptProbeMediaRequestCount += 1;
      if (decision.blocked) {
        _interceptProbeMediaBlockedCount += 1;
      }
      if (!decision.blocked && decision.reason == 'overblock_fail_open') {
        _interceptProbeFailOpenAllowCount += 1;
      }
    }
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

  void _flushInterceptProbeWindow(int nowMs) {
    if (_interceptProbeRequestCount > 0 &&
        _interceptProbeLogCount < _maxInterceptProbeLogs) {
      _interceptProbeLogCount += 1;
      final mediaBlockPct = _interceptProbeMediaRequestCount <= 0
          ? 0
          : (_interceptProbeMediaBlockedCount * 100) ~/
                _interceptProbeMediaRequestCount;
      _logger.log(
        'intercept_probe window=10s req=$_interceptProbeRequestCount blocked=$_interceptProbeBlockedCount sw=$_interceptProbeServiceWorkerCount adSignal=$_interceptProbeAdShowingCount stalled=$_interceptProbeStalledCount cache=$_interceptProbeCacheHitCount mediaReq=$_interceptProbeMediaRequestCount mediaBlocked=$_interceptProbeMediaBlockedCount mediaBlockPct=$mediaBlockPct failOpenAllow=$_interceptProbeFailOpenAllowCount topType=${_topSummary(_interceptProbeTypeCounts, limit: 4)} topReason=${_topSummary(_interceptProbeReasonCounts, limit: 4)}',
      );
    }
    _interceptProbeWindowStartMs = nowMs;
    _interceptProbeRequestCount = 0;
    _interceptProbeBlockedCount = 0;
    _interceptProbeServiceWorkerCount = 0;
    _interceptProbeAdShowingCount = 0;
    _interceptProbeStalledCount = 0;
    _interceptProbeCacheHitCount = 0;
    _interceptProbeMediaRequestCount = 0;
    _interceptProbeMediaBlockedCount = 0;
    _interceptProbeFailOpenAllowCount = 0;
    _interceptProbeTypeCounts.clear();
    _interceptProbeReasonCounts.clear();
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

  bool _containsAnyQueryKeyInRawQuery(String rawQuery, List<String> keys) {
    return _queryUtils.containsAnyQueryKeyInRawQuery(rawQuery, keys);
  }

  int _countQueryKeyHitsInRawQuery(
    String rawQuery,
    List<String> keys, {
    int maxHits = 999,
  }) {
    return _queryUtils.countQueryKeyHitsInRawQuery(
      rawQuery,
      keys,
      maxHits: maxHits,
    );
  }

  bool _containsAllQueryKeysInRawQuery(String rawQuery, List<String> keys) {
    return _queryUtils.containsAllQueryKeysInRawQuery(rawQuery, keys);
  }

  bool _containsAdLikeQueryKey(String rawQuery) {
    return _queryUtils.containsAdLikeQueryKey(rawQuery);
  }

  bool _containsAdLikeQueryValue(String rawQuery) {
    return _queryUtils.containsAdLikeQueryValue(rawQuery);
  }

  bool _containsQueryKeyWithValuePrefix(
    String rawQuery, {
    required String key,
    required String valuePrefix,
  }) {
    return _queryUtils.containsQueryKeyWithValuePrefix(
      rawQuery,
      key: key,
      valuePrefix: valuePrefix,
    );
  }

  bool _containsQueryKeyWithAnyValue(
    String rawQuery, {
    required String key,
    required List<String> candidateValues,
  }) {
    return _queryUtils.containsQueryKeyWithAnyValue(
      rawQuery,
      key: key,
      candidateValues: candidateValues,
    );
  }

  bool _containsQueryKeyValueContainingAllTokens(
    String rawQuery, {
    required String key,
    required List<String> tokens,
  }) {
    return _queryUtils.containsQueryKeyValueContainingAllTokens(
      rawQuery,
      key: key,
      tokens: tokens,
    );
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
      'googlevideo allow reason=$reason type=${request.resourceType.toLowerCase()} host=${uri.host} path=${uri.path} queryKeys=${_queryKeysSummary(uri.query)} adShowing=${request.adShowing} stalled=${request.playbackStalled} source=$sourceLabel sw=${request.fromServiceWorker}',
    );
    final markerHints = _adLikeMarkerHints(uri.query);
    if (request.adShowing) {
      if (reason == 'engine_allow' &&
          markerHints.isEmpty &&
          _googleVideoAdWindowFullQueryLogCount <
              _maxGoogleVideoAdWindowFullQueryLogs) {
        _googleVideoAdWindowFullQueryLogCount += 1;
        _logger.log(
          'googlevideo allow ad-window no-marker reason=$reason source=$sourceLabel signalKey=${request.adSignalKey ?? 'none'} fullQuery=${uri.query.isEmpty ? 'none' : uri.query}',
        );
      }
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
    return _queryUtils.adLikeMarkerHints(rawQuery, limit: limit);
  }

  String _queryKeysSummary(String rawQuery, {int limit = 10}) {
    return _queryUtils.queryKeysSummary(rawQuery, limit: limit);
  }

  String _cacheKey(AdblockRequestContext request) {
    final sourceHost = request.sourceUrl?.host.toLowerCase() ?? 'none';
    final signalKey = (request.adSignalKey ?? '').trim().toLowerCase();
    return '${request.resourceType.toLowerCase()}|${request.uri.scheme.toLowerCase()}://${request.uri.host.toLowerCase()}${request.uri.path}?${request.uri.query}|$sourceHost|ad=${request.adShowing}|stall=${request.playbackStalled}|sig=${signalKey.isEmpty ? 'none' : signalKey}|sw=${request.fromServiceWorker}';
  }

  AdblockDecision? _readCache(String key) {
    return _decisionCache.read(key);
  }

  void _writeCache(String key, AdblockDecision decision) {
    _decisionCache.write(key, decision);
  }
}
