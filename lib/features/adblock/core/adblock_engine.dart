import 'dart:collection';

import '../../domain_lock/domain_policy_service.dart';
import '../adblock_engine_bridge.dart';
import '../config/filter_source_manager.dart';
import '../crowd/storage/learned_signature_repository.dart';
import '../filters/filter_compiler.dart';
import '../filters/filter_parser.dart';
import '../filters/rule_models.dart';
import '../filters/rule_normalizer.dart';
import '../injection/scriptlet_engine.dart';
import '../intercept/request_interceptor.dart';
import '../matchers/cosmetic_matcher.dart';
import '../matchers/request_matcher.dart';
import '../models/adblock_rule.dart';
import 'adblock_config.dart';
import 'adblock_debug_logger.dart';
import 'adblock_metrics.dart';
import 'adblock_request_runtime_engine.dart';
import 'engine_request_policy.dart';
import 'engine_adapter.dart';
import 'filter_compiler.dart' as legacy;
import 'request_runtime_models.dart';
import 'types.dart';

class AdblockEngine
    implements
        AdblockEngineBridge,
        AdblockRuntimeEngine,
        AdblockRequestRuntimeEngine,
        RequestNormalizationObserver {
  AdblockEngine({
    required FilterSourceManager sourceManager,
    required FilterParser parser,
    RuleNormalizer? normalizer,
    required IndexedFilterCompiler compiler,
    required RequestMatcher requestMatcher,
    required CosmeticMatcher cosmeticMatcher,
    required ScriptletEngine scriptletEngine,
    required RequestInterceptor requestInterceptor,
    required EngineAdapter bridge,
    required AdblockDebugLogger logger,
    required DomainPolicyService domainPolicyService,
    required AdblockMetricsCollector metrics,
    required AdblockConfig initialConfig,
    LearnedSignatureRepository? learnedSignatureRepository,
    legacy.FilterCompiler? legacyCompiler,
  }) : _sourceManager = sourceManager,
       _parser = parser,
       _normalizer = normalizer ?? const RuleNormalizer(),
       _compiler = compiler,
       _requestMatcher = requestMatcher,
       _cosmeticMatcher = cosmeticMatcher,
       _scriptletEngine = scriptletEngine,
       _requestInterceptor = requestInterceptor,
       _bridge = bridge,
       _logger = logger,
       _legacyCompiler = legacyCompiler ?? const legacy.FilterCompiler(),
       _requestPolicy = EngineRequestPolicy(
         domainPolicyService: domainPolicyService,
         logger: logger,
         metrics: metrics,
         learnedSignatureRepository: learnedSignatureRepository,
         requestInterceptor: requestInterceptor,
       ) {
    _requestPolicy.setEngine(this);
    _requestPolicy.setConfig(initialConfig);
    _config = initialConfig;
  }

  final FilterSourceManager _sourceManager;
  final FilterParser _parser;
  final RuleNormalizer _normalizer;
  final IndexedFilterCompiler _compiler;
  final RequestMatcher _requestMatcher;
  final CosmeticMatcher _cosmeticMatcher;
  final ScriptletEngine _scriptletEngine;
  final RequestInterceptor _requestInterceptor;
  final EngineAdapter _bridge;
  final AdblockDebugLogger _logger;
  final legacy.FilterCompiler _legacyCompiler;
  final EngineRequestPolicy _requestPolicy;
  final LinkedHashMap<String, _DecisionCacheEntry> _decisionCache =
      LinkedHashMap<String, _DecisionCacheEntry>();

  static const Duration _decisionCacheTtl = Duration(seconds: 10);
  static const int _maxDecisionCacheEntries = 2400;

  AdblockConfig? _config;
  FilterSourceSnapshot? _sourceSnapshot;
  CompiledFilterSet _compiledSet = CompiledFilterSet.empty();
  bool _initialized = false;
  bool _disposed = false;
  bool _bridgeInitialized = false;
  int _activeRuleCount = 0;
  Future<void>? _initializeFuture;

  int _totalRequestEvaluations = 0;
  int _decisionCacheHits = 0;
  int _decisionCacheMisses = 0;
  int _regexFallbackCount = 0;
  int _allowDecisionCount = 0;
  int _blockDecisionCount = 0;
  int _redirectDecisionCount = 0;
  int _rewriteDecisionCount = 0;
  int _bridgeEvaluationCount = 0;
  int _bridgeErrorCount = 0;
  int _bridgeAllowCount = 0;
  int _bridgeBlockCount = 0;
  int _bridgeRedirectCount = 0;
  int _bridgeRewriteCount = 0;
  int _bridgeFallbackCount = 0;
  int _candidateTotalCount = 0;
  int _evaluatedTotalCount = 0;
  int _maxCandidateCount = 0;
  int _maxEvaluatedCount = 0;
  int _lastNormalizationMicros = 0;
  int _lastCandidateLookupMicros = 0;
  int _lastCandidateEvaluationMicros = 0;
  int _lastBridgeEvaluationMicros = 0;
  int _lastCompileDurationMs = 0;
  int _compileCount = 0;
  int _lastCompiledNetworkRuleCount = 0;
  int _lastCompiledCosmeticRuleCount = 0;
  int _lastCompiledScriptletRuleCount = 0;
  int _lastCosmeticPayloadSize = 0;
  int _lastScriptletPayloadSize = 0;

  bool get initialized => _initialized;
  bool get usingNativeEngine => _bridgeInitialized && _bridge.usingNativeEngine;
  String get activeRevision => _compiledSet.revision;
  int get activeRuleCount => _activeRuleCount;
  List<String> get loadedSources =>
      _sourceSnapshot?.loadedSources ?? const <String>[];
  bool get usedCachedList => _sourceSnapshot?.usedCachedData ?? false;
  bool get firstPartyHeuristicProfileEnabled =>
      _sourceSnapshot?.firstPartyHeuristicsProfileEnabled ?? false;

  CompiledFilterSet get compiledSet => _compiledSet;

  Map<String, dynamic> getBridgeDebugSnapshot() => _bridge.debugSnapshot;

  Future<void> initializeCore({required AdblockConfig config}) async {
    if (_disposed) {
      throw StateError('AdblockEngine already disposed');
    }
    _config = config;
    _requestPolicy.setConfig(config);
    if (_initialized) {
      return;
    }
    final pending = _initializeFuture;
    if (pending != null) {
      return pending;
    }
    final future = _loadAndCompile(config: config);
    _initializeFuture = future;
    try {
      await future;
      _initialized = true;
    } finally {
      _initializeFuture = null;
    }
  }

  Future<void> updateFilterSources() async {
    final config = _config;
    if (config == null) {
      return;
    }
    await _loadAndCompile(config: config, refreshSources: true);
    _initialized = true;
  }

  Future<void> compileFilters() async {
    await compile();
  }

  Future<void> compile() async {
    final config = _config;
    if (config == null) {
      return;
    }
    await _loadAndCompile(config: config);
    _initialized = true;
  }

  void addFilterList(String listText, FilterListMetadata metadata) {
    _sourceManager.addCustomList(listText, metadata: metadata);
  }

  EngineStatsSnapshot getEngineStats() {
    return EngineStatsSnapshot(
      totalRequestEvaluations: _totalRequestEvaluations,
      decisionCacheHits: _decisionCacheHits,
      decisionCacheMisses: _decisionCacheMisses,
      regexFallbackCount: _regexFallbackCount,
      allowDecisionCount: _allowDecisionCount,
      blockDecisionCount: _blockDecisionCount,
      redirectDecisionCount: _redirectDecisionCount,
      rewriteDecisionCount: _rewriteDecisionCount,
      bridgeEvaluationCount: _bridgeEvaluationCount,
      bridgeErrorCount: _bridgeErrorCount,
      bridgeAllowCount: _bridgeAllowCount,
      bridgeBlockCount: _bridgeBlockCount,
      bridgeRedirectCount: _bridgeRedirectCount,
      bridgeRewriteCount: _bridgeRewriteCount,
      bridgeFallbackCount: _bridgeFallbackCount,
      candidateTotalCount: _candidateTotalCount,
      evaluatedTotalCount: _evaluatedTotalCount,
      maxCandidateCount: _maxCandidateCount,
      maxEvaluatedCount: _maxEvaluatedCount,
      lastNormalizationMicros: _lastNormalizationMicros,
      lastCandidateLookupMicros: _lastCandidateLookupMicros,
      lastCandidateEvaluationMicros: _lastCandidateEvaluationMicros,
      lastBridgeEvaluationMicros: _lastBridgeEvaluationMicros,
      lastCompileDurationMs: _lastCompileDurationMs,
      compileCount: _compileCount,
      lastCompiledNetworkRuleCount: _lastCompiledNetworkRuleCount,
      lastCompiledCosmeticRuleCount: _lastCompiledCosmeticRuleCount,
      lastCompiledScriptletRuleCount: _lastCompiledScriptletRuleCount,
      lastCosmeticPayloadSize: _lastCosmeticPayloadSize,
      lastScriptletPayloadSize: _lastScriptletPayloadSize,
    );
  }

  @override
  Future<AdblockDecision> evaluateAdblockRequest(
    AdblockRequestContext request,
  ) {
    return _requestPolicy.evaluate(request);
  }

  @override
  void recordRequestNormalizationMicros(int micros) {
    if (micros >= 0) {
      _lastNormalizationMicros = micros;
    }
  }

  @override
  void setRuntimeConfig(AdblockConfig config) {
    _config = config;
    _decisionCache.clear();
    _requestPolicy.setConfig(config);
  }

  @override
  void setFirstPartyHeuristicProfile(bool enabled) {
    _requestPolicy.setFirstPartyHeuristicProfile(enabled);
  }

  @override
  void clearRuntimeCache() {
    _decisionCache.clear();
    _requestPolicy.clearCache();
  }

  @override
  void onPlaybackDebugSignal(Map<String, dynamic> payload, {Uri? pageUri}) {
    _requestPolicy.onPlaybackDebugSignal(payload, pageUri: pageUri);
  }

  @override
  Future<RequestDecision> evaluateRequest(RequestContext context) async {
    _totalRequestEvaluations += 1;
    if (_disposed) {
      return RequestDecision.allow(reason: 'disposed');
    }
    if (!_initialized) {
      return RequestDecision.allow(reason: 'not_initialized');
    }

    final cacheKey = _decisionCacheKey(context);
    final cached = _readDecisionCache(cacheKey);
    if (cached != null) {
      _decisionCacheHits += 1;
      return RequestDecision(
        action: cached.action,
        reason: cached.reason,
        matchedRule: cached.matchedRule,
        exceptionRule: cached.exceptionRule,
        redirectDataUrl: cached.redirectDataUrl,
        rewrittenUrl: cached.rewrittenUrl,
        fromCache: true,
        candidateCount: cached.candidateCount,
        evaluatedCount: cached.evaluatedCount,
      );
    }
    _decisionCacheMisses += 1;

    final candidateLookupStopwatch = Stopwatch()..start();
    final candidates = _requestMatcher.findCandidates(context, _compiledSet);
    candidateLookupStopwatch.stop();
    _lastCandidateLookupMicros = candidateLookupStopwatch.elapsedMicroseconds;

    final candidateEvalStopwatch = Stopwatch()..start();
    final localDecision = _requestMatcher.evaluateCandidates(
      context,
      _compiledSet,
      candidates,
    );
    candidateEvalStopwatch.stop();
    _lastCandidateEvaluationMicros = candidateEvalStopwatch.elapsedMicroseconds;
    if (localDecision.usedRegexFallback) {
      _regexFallbackCount += 1;
    }
    _candidateTotalCount += localDecision.candidateCount;
    _evaluatedTotalCount += localDecision.evaluatedCount;
    if (localDecision.candidateCount > _maxCandidateCount) {
      _maxCandidateCount = localDecision.candidateCount;
    }
    if (localDecision.evaluatedCount > _maxEvaluatedCount) {
      _maxEvaluatedCount = localDecision.evaluatedCount;
    }

    final localRequestDecision = _networkDecisionToRequestDecision(
      localDecision,
    );

    final bridgeDecision = await _evaluateWithBridge(context);
    final finalDecision = _resolveFinalDecision(
      localDecision: localRequestDecision,
      bridgeDecision: bridgeDecision,
      candidateCount: localDecision.candidateCount,
      evaluatedCount: localDecision.evaluatedCount,
    );
    _recordFinalAction(finalDecision.action);
    _writeDecisionCache(cacheKey, finalDecision);
    return finalDecision;
  }

  Future<NetworkMatchDecision> shouldBlockRequest(
    RequestContext context,
  ) async {
    final decision = await evaluateRequest(context);
    switch (decision.action) {
      case DecisionAction.allow:
        return NetworkMatchDecision.allow(
          reason: decision.reason,
          exceptionRule: decision.exceptionRule,
          candidateCount: decision.candidateCount,
          evaluatedCount: decision.evaluatedCount,
        );
      case DecisionAction.block:
        return NetworkMatchDecision(
          blocked: true,
          action: DecisionAction.block,
          reason: decision.reason,
          matchedRule: decision.matchedRule,
          exceptionRule: decision.exceptionRule,
          candidateCount: decision.candidateCount,
          evaluatedCount: decision.evaluatedCount,
        );
      case DecisionAction.redirect:
        return NetworkMatchDecision(
          blocked: true,
          action: DecisionAction.redirect,
          reason: decision.reason,
          matchedRule: decision.matchedRule,
          redirectDataUrl: decision.redirectDataUrl,
          candidateCount: decision.candidateCount,
          evaluatedCount: decision.evaluatedCount,
        );
      case DecisionAction.rewriteResponse:
        return NetworkMatchDecision(
          blocked: false,
          action: DecisionAction.rewriteResponse,
          reason: decision.reason,
          matchedRule: decision.matchedRule,
          rewrittenUrl: decision.rewrittenUrl,
          candidateCount: decision.candidateCount,
          evaluatedCount: decision.evaluatedCount,
        );
    }
  }

  Future<CosmeticRules> getCosmeticRules(PageContext pageContext) async {
    final payload = await getCosmeticPayload(pageContext);
    if (payload.isEmpty) {
      return CosmeticRules.empty();
    }
    return CosmeticRules(
      selectors: payload.hideSelectors,
      exceptions: payload.exceptions,
      generichide: payload.generichide,
    );
  }

  Future<InjectionScripts> getInjectionScripts(PageContext pageContext) async {
    final payload = await getScriptletPayload(pageContext);
    if (payload.isEmpty) {
      return InjectionScripts.empty();
    }
    return InjectionScripts(scripts: payload.scripts);
  }

  @override
  Future<CosmeticPayload> getCosmeticPayload(PageContext pageContext) async {
    final localRules = _cosmeticMatcher.match(pageContext, _compiledSet);
    final hideSelectors = <String>{...localRules.selectors};
    final proceduralActions = <String>{};
    final exceptions = <String>{...localRules.exceptions};
    var generichide = localRules.generichide;

    if (_bridgeInitialized) {
      try {
        final native = await _bridge.getCosmeticResources(pageContext.url);
        if (native != null) {
          hideSelectors.addAll(native.hideSelectors);
          proceduralActions.addAll(native.proceduralActions);
          exceptions.addAll(native.exceptions);
          generichide = generichide || native.generichide;
        }
      } catch (_) {}
    }
    hideSelectors.removeAll(exceptions);
    final payload = CosmeticPayload(
      hideSelectors: Set<String>.unmodifiable(hideSelectors),
      proceduralActions: Set<String>.unmodifiable(proceduralActions),
      exceptions: Set<String>.unmodifiable(exceptions),
      generichide: generichide,
    );
    _lastCosmeticPayloadSize =
        payload.hideSelectors.length +
        payload.proceduralActions.length +
        payload.exceptions.length;
    return payload;
  }

  @override
  Future<ScriptletPayload> getScriptletPayload(PageContext pageContext) async {
    final localPayload = _scriptletEngine.resolvePayload(
      pageContext,
      _compiledSet,
    );
    final scripts = <String>[...localPayload.scripts];
    var runtimeEnabled = localPayload.runtimeEnabled;
    if (_bridgeInitialized) {
      try {
        final native = await _bridge.getCosmeticResources(pageContext.url);
        final injected = (native?.injectedScript ?? '').trim();
        if (injected.isNotEmpty) {
          scripts.add(injected);
        }
      } catch (_) {}
    }
    final deduped = <String>{};
    final unique = <String>[];
    for (final script in scripts) {
      final normalized = script.trim();
      if (normalized.isEmpty || !deduped.add(normalized)) {
        continue;
      }
      unique.add(normalized);
    }
    if (_config != null) {
      runtimeEnabled = _config!.enabled && _config!.scriptletsEnabled;
    }
    final payload = ScriptletPayload(
      scripts: List<String>.unmodifiable(unique),
      runtimeEnabled: runtimeEnabled,
    );
    _lastScriptletPayloadSize = payload.scripts.length;
    return payload;
  }

  Map<String, dynamic> serialize() {
    final customMetadata = _sourceManager
        .metadata()
        .map(
          (entry) => <String, dynamic>{
            'id': entry.id,
            'title': entry.title,
            'version': entry.version,
            'enabled': entry.enabled,
            'updatedAtMs': entry.updatedAtMs,
            'source': entry.source,
          },
        )
        .toList(growable: false);
    return <String, dynamic>{
      'revision': _compiledSet.revision,
      'ruleCount': _activeRuleCount,
      'loadedSources': loadedSources,
      'customMetadata': customMetadata,
    };
  }

  Future<void> deserialize(Map<String, dynamic> payload) async {
    final metadataEntries = payload['customMetadata'];
    if (metadataEntries is List) {
      for (final entry in metadataEntries) {
        if (entry is! Map) {
          continue;
        }
        final mapped = entry.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        final id = mapped['id']?.toString().trim() ?? '';
        if (id.isEmpty) {
          continue;
        }
        _sourceManager.addCustomList(
          '',
          metadata: FilterListMetadata(
            id: id,
            title: mapped['title']?.toString() ?? id,
            version: mapped['version']?.toString() ?? 'unknown',
            enabled: mapped['enabled'] == true,
            updatedAtMs: (mapped['updatedAtMs'] as num?)?.toInt() ?? 0,
            source: mapped['source']?.toString() ?? 'deserialize',
          ),
        );
      }
    }
    await compile();
  }

  Future<void> _loadAndCompile({
    required AdblockConfig config,
    bool refreshSources = false,
  }) async {
    _decisionCache.clear();
    final sourceSnapshot = refreshSources
        ? await _sourceManager.refresh(config: config, logger: _logger)
        : await _sourceManager.load(config: config, logger: _logger);
    _sourceSnapshot = sourceSnapshot;
    _activeRuleCount = sourceSnapshot.lines.length;
    await _compileSnapshot(sourceSnapshot);
  }

  Future<void> _compileSnapshot(FilterSourceSnapshot sourceSnapshot) async {
    final compileStopwatch = Stopwatch()..start();
    final parsed = _parser.parse(sourceSnapshot.lines);
    final normalized = _normalizer.normalize(parsed);
    _compiledSet = _compiler.compile(
      parsed: normalized,
      rawLines: sourceSnapshot.lines,
    );
    compileStopwatch.stop();
    _lastCompileDurationMs = compileStopwatch.elapsedMilliseconds;
    _compileCount += 1;
    _lastCompiledNetworkRuleCount = _compiledSet.networkRules.length;
    _lastCompiledCosmeticRuleCount = _compiledSet.cosmeticRules.length;
    _lastCompiledScriptletRuleCount = _compiledSet.scriptInjectionRules.length;

    final legacyCompiled = _legacyCompiler.compile(sourceSnapshot.lines);
    if (legacyCompiled.rules.isEmpty) {
      _logger.log(
        'core_engine compile revision=${_compiledSet.revision} network=${_compiledSet.networkRules.length} cosmetic=${_compiledSet.cosmeticRules.length} scriptlets=${_compiledSet.scriptInjectionRules.length} legacyRules=0',
      );
    }

    try {
      await _bridge.initialize(
        legacyCompiled.rules,
        rawFilterText: sourceSnapshot.rawFilterText,
        resourcesJson: sourceSnapshot.resourcesJson,
        catalogSourcesJson: sourceSnapshot.catalogSourcesJson,
        serializedEngineBase64: sourceSnapshot.serializedEngineBase64,
        enabledTags: sourceSnapshot.enabledTags,
      );
      _bridgeInitialized = true;
      if (_bridge.usingNativeEngine) {
        final serialized = (await _bridge.serializeEngine())?.trim() ?? '';
        if (serialized.isNotEmpty &&
            sourceSnapshot.engineSnapshotKey.isNotEmpty) {
          await _sourceManager.persistSerializedEngineSnapshot(
            snapshotKey: sourceSnapshot.engineSnapshotKey,
            serializedEngineBase64: serialized,
            logger: _logger,
          );
        }
      }
      _logger.log(
        'core_engine initialized revision=${_compiledSet.revision} rules=${legacyCompiled.rules.length} native=${_bridge.usingNativeEngine}',
      );
    } catch (_) {
      _bridgeInitialized = false;
      _logger.log('core_engine bridge init failed -> matcher only mode');
    }
  }

  Future<RequestDecision> _evaluateWithBridge(RequestContext context) async {
    if (!_bridgeInitialized) {
      _bridgeFallbackCount += 1;
      return RequestDecision.allow(reason: 'bridge_unavailable');
    }
    try {
      final bridgeWatch = Stopwatch()..start();
      _bridgeEvaluationCount += 1;
      final result = await _bridge.evaluateRequestDetailed(
        context.url,
        resourceType: context.resourceType,
        sourceUrl: context.frameUrl ?? context.topLevelUrl,
      );
      bridgeWatch.stop();
      _lastBridgeEvaluationMicros = bridgeWatch.elapsedMicroseconds;
      final redirect = (result.redirectDataUrl ?? '').trim();
      final rewrite = (result.rewrittenUrl ?? '').trim();
      if (redirect.isNotEmpty) {
        _bridgeRedirectCount += 1;
        return RequestDecision.redirect(
          reason: 'engine_redirect',
          redirectDataUrl: redirect,
          matchedRule: result.matchedRule,
        );
      }
      if (rewrite.isNotEmpty) {
        _bridgeRewriteCount += 1;
        return RequestDecision.rewriteResponse(
          reason: 'engine_rewrite',
          rewrittenUrl: rewrite,
          matchedRule: result.matchedRule,
        );
      }
      if (result.blocked) {
        _bridgeBlockCount += 1;
        return RequestDecision.block(
          reason: 'engine_match',
          matchedRule: result.matchedRule,
        );
      }
      if ((result.exceptionRule ?? '').trim().isNotEmpty) {
        _bridgeAllowCount += 1;
        return RequestDecision.allow(
          reason: 'engine_exception',
          exceptionRule: result.exceptionRule,
        );
      }
      _bridgeAllowCount += 1;
      return RequestDecision.allow(reason: 'engine_allow');
    } catch (_) {
      _bridgeErrorCount += 1;
      return RequestDecision.allow(reason: 'engine_error_allow');
    }
  }

  void _recordFinalAction(DecisionAction action) {
    switch (action) {
      case DecisionAction.allow:
        _allowDecisionCount += 1;
        break;
      case DecisionAction.block:
        _blockDecisionCount += 1;
        break;
      case DecisionAction.redirect:
        _redirectDecisionCount += 1;
        break;
      case DecisionAction.rewriteResponse:
        _rewriteDecisionCount += 1;
        break;
    }
  }

  RequestDecision _networkDecisionToRequestDecision(
    NetworkMatchDecision decision,
  ) {
    final candidateCount = decision.candidateCount;
    final evaluatedCount = decision.evaluatedCount;
    if ((decision.exceptionRule ?? '').trim().isNotEmpty) {
      return RequestDecision.allow(
        reason: decision.reason,
        exceptionRule: decision.exceptionRule,
        candidateCount: candidateCount,
        evaluatedCount: evaluatedCount,
      );
    }

    switch (decision.action) {
      case DecisionAction.allow:
        return RequestDecision.allow(
          reason: decision.reason,
          candidateCount: candidateCount,
          evaluatedCount: evaluatedCount,
        );
      case DecisionAction.block:
        return RequestDecision.block(
          reason: decision.reason,
          matchedRule: decision.matchedRule,
          candidateCount: candidateCount,
          evaluatedCount: evaluatedCount,
        );
      case DecisionAction.redirect:
        final redirect = (decision.redirectDataUrl ?? '').trim();
        if (redirect.isEmpty) {
          return RequestDecision.block(
            reason: 'compiled_network_redirect_invalid_target',
            matchedRule: decision.matchedRule,
            candidateCount: candidateCount,
            evaluatedCount: evaluatedCount,
          );
        }
        return RequestDecision.redirect(
          reason: decision.reason,
          redirectDataUrl: redirect,
          matchedRule: decision.matchedRule,
          candidateCount: candidateCount,
          evaluatedCount: evaluatedCount,
        );
      case DecisionAction.rewriteResponse:
        final rewrite = (decision.rewrittenUrl ?? '').trim();
        if (rewrite.isEmpty) {
          return RequestDecision.allow(
            reason: 'compiled_network_rewrite_invalid_target',
            candidateCount: candidateCount,
            evaluatedCount: evaluatedCount,
          );
        }
        return RequestDecision.rewriteResponse(
          reason: decision.reason,
          rewrittenUrl: rewrite,
          matchedRule: decision.matchedRule,
          candidateCount: candidateCount,
          evaluatedCount: evaluatedCount,
        );
    }
  }

  RequestDecision _resolveFinalDecision({
    required RequestDecision localDecision,
    required RequestDecision bridgeDecision,
    required int candidateCount,
    required int evaluatedCount,
  }) {
    if (_isBridgeDecisionAuthoritative(bridgeDecision)) {
      return RequestDecision(
        action: bridgeDecision.action,
        reason: bridgeDecision.reason,
        matchedRule: bridgeDecision.matchedRule,
        exceptionRule: bridgeDecision.exceptionRule,
        redirectDataUrl: bridgeDecision.redirectDataUrl,
        rewrittenUrl: bridgeDecision.rewrittenUrl,
        candidateCount: candidateCount,
        evaluatedCount: evaluatedCount,
      );
    }

    if ((localDecision.exceptionRule ?? '').trim().isNotEmpty) {
      return RequestDecision.allow(
        reason: localDecision.reason,
        exceptionRule: localDecision.exceptionRule,
        candidateCount: candidateCount,
        evaluatedCount: evaluatedCount,
      );
    }

    if (localDecision.action != DecisionAction.allow) {
      return RequestDecision(
        action: localDecision.action,
        reason: localDecision.reason,
        matchedRule: localDecision.matchedRule,
        exceptionRule: localDecision.exceptionRule,
        redirectDataUrl: localDecision.redirectDataUrl,
        rewrittenUrl: localDecision.rewrittenUrl,
        candidateCount: candidateCount,
        evaluatedCount: evaluatedCount,
      );
    }

    return RequestDecision.allow(
      reason: localDecision.reason,
      candidateCount: candidateCount,
      evaluatedCount: evaluatedCount,
    );
  }

  bool _isBridgeDecisionAuthoritative(RequestDecision bridgeDecision) {
    final reason = bridgeDecision.reason.trim().toLowerCase();
    return reason != 'bridge_unavailable' && reason != 'engine_error_allow';
  }

  String _decisionCacheKey(RequestContext context) {
    final source = context.frameUrl ?? context.topLevelUrl;
    final sourceLabel = source == null
        ? 'none'
        : '${source.scheme.toLowerCase()}://${source.host.toLowerCase()}${source.path}${source.hasQuery ? '?${source.query}' : ''}';
    return '${context.method}|${context.resourceType}|${context.isThirdParty ? 'tp' : 'fp'}|${context.url.toString()}|$sourceLabel';
  }

  _DecisionCacheEntry? _readDecisionCache(String cacheKey) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final entry = _decisionCache.remove(cacheKey);
    if (entry == null) {
      return null;
    }
    if (entry.expiresAtMs <= now) {
      return null;
    }
    _decisionCache[cacheKey] = entry;
    return entry;
  }

  void _writeDecisionCache(String cacheKey, RequestDecision decision) {
    _decisionCache.remove(cacheKey);
    _decisionCache[cacheKey] = _DecisionCacheEntry(
      action: decision.action,
      reason: decision.reason,
      matchedRule: decision.matchedRule,
      exceptionRule: decision.exceptionRule,
      redirectDataUrl: decision.redirectDataUrl,
      rewrittenUrl: decision.rewrittenUrl,
      candidateCount: decision.candidateCount,
      evaluatedCount: decision.evaluatedCount,
      expiresAtMs: DateTime.now().add(_decisionCacheTtl).millisecondsSinceEpoch,
    );
    while (_decisionCache.length > _maxDecisionCacheEntries) {
      _decisionCache.remove(_decisionCache.keys.first);
    }
  }

  @override
  Future<bool> isAvailable() {
    return _bridge.isAvailable();
  }

  @override
  Future<void> initialize(
    List<AdblockRule> rules, {
    String? rawFilterText,
    String? resourcesJson,
    String? catalogSourcesJson,
    String? serializedEngineBase64,
    List<String> enabledTags = const <String>[],
  }) async {
    try {
      await _bridge.initialize(
        rules,
        rawFilterText: rawFilterText,
        resourcesJson: resourcesJson,
        catalogSourcesJson: catalogSourcesJson,
        serializedEngineBase64: serializedEngineBase64,
        enabledTags: enabledTags,
      );
      _bridgeInitialized = true;
    } catch (_) {
      _bridgeInitialized = false;
      rethrow;
    }
  }

  @override
  Future<bool> shouldBlock(
    Uri uri, {
    required String resourceType,
    Uri? sourceUrl,
  }) async {
    final decision = await evaluateRequestDetailed(
      uri,
      resourceType: resourceType,
      sourceUrl: sourceUrl,
    );
    return decision.blocked;
  }

  @override
  Future<AdblockEngineRequestResult> evaluateRequestDetailed(
    Uri uri, {
    required String resourceType,
    Uri? sourceUrl,
  }) async {
    final normalizeStopwatch = Stopwatch()..start();
    final context = _requestInterceptor.normalize(
      url: uri,
      resourceType: resourceType,
      frameUrl: sourceUrl,
      topLevelUrl: sourceUrl,
    );
    normalizeStopwatch.stop();
    recordRequestNormalizationMicros(normalizeStopwatch.elapsedMicroseconds);
    final decision = await shouldBlockRequest(context);
    return AdblockEngineRequestResult(
      blocked: decision.blocked,
      matched: decision.blocked,
      redirectDataUrl: decision.redirectDataUrl,
      rewrittenUrl: decision.rewrittenUrl,
      important: false,
      exceptionRule: decision.exceptionRule,
      matchedRule: decision.matchedRule,
    );
  }

  @override
  Future<AdblockCosmeticResources?> getCosmeticResources(Uri pageUri) async {
    if (_disposed || !_initialized) {
      return null;
    }
    final pageContext = PageContext(
      url: pageUri,
      hostname: pageUri.host.toLowerCase(),
      domain: pageUri.host.toLowerCase(),
      topLevelUrl: pageUri,
      headers: const <String, String>{},
    );
    final cosmetic = await getCosmeticRules(pageContext);
    final scripts = await getInjectionScripts(pageContext);
    if (cosmetic.selectors.isEmpty &&
        cosmetic.exceptions.isEmpty &&
        scripts.scripts.isEmpty) {
      return null;
    }
    return AdblockCosmeticResources(
      hideSelectors: cosmetic.selectors,
      proceduralActions: const <String>{},
      exceptions: cosmetic.exceptions,
      injectedScript: scripts.scripts.join('\n'),
      generichide: cosmetic.generichide,
    );
  }

  @override
  Future<List<String>> getHiddenClassIdSelectors(
    Uri pageUri, {
    required List<String> classes,
    required List<String> ids,
    Set<String> exceptions = const <String>{},
  }) async {
    if (!_bridgeInitialized) {
      return const <String>[];
    }
    return _bridge.getHiddenClassIdSelectors(
      pageUri,
      classes: classes,
      ids: ids,
      exceptions: exceptions,
    );
  }

  @override
  Future<String?> getCspDirectives(
    Uri uri, {
    required String resourceType,
    Uri? sourceUrl,
  }) async {
    if (!_bridgeInitialized) {
      return null;
    }
    return _bridge.getCspDirectives(
      uri,
      resourceType: resourceType,
      sourceUrl: sourceUrl,
    );
  }

  @override
  Future<String?> serializeEngine() async {
    if (!_bridgeInitialized) {
      return null;
    }
    return _bridge.serializeEngine();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    try {
      await _bridge.dispose();
    } catch (_) {}
    _compiledSet = CompiledFilterSet.empty();
    _decisionCache.clear();
    _requestPolicy.clearCache();
    _sourceSnapshot = null;
    _initialized = false;
    _bridgeInitialized = false;
    _activeRuleCount = 0;
    _totalRequestEvaluations = 0;
    _decisionCacheHits = 0;
    _decisionCacheMisses = 0;
    _regexFallbackCount = 0;
    _allowDecisionCount = 0;
    _blockDecisionCount = 0;
    _redirectDecisionCount = 0;
    _rewriteDecisionCount = 0;
    _bridgeEvaluationCount = 0;
    _bridgeErrorCount = 0;
    _bridgeAllowCount = 0;
    _bridgeBlockCount = 0;
    _bridgeRedirectCount = 0;
    _bridgeRewriteCount = 0;
    _bridgeFallbackCount = 0;
    _candidateTotalCount = 0;
    _evaluatedTotalCount = 0;
    _maxCandidateCount = 0;
    _maxEvaluatedCount = 0;
    _lastNormalizationMicros = 0;
    _lastCandidateLookupMicros = 0;
    _lastCandidateEvaluationMicros = 0;
    _lastBridgeEvaluationMicros = 0;
    _lastCompileDurationMs = 0;
    _compileCount = 0;
    _lastCompiledNetworkRuleCount = 0;
    _lastCompiledCosmeticRuleCount = 0;
    _lastCompiledScriptletRuleCount = 0;
    _lastCosmeticPayloadSize = 0;
    _lastScriptletPayloadSize = 0;
  }
}

class _DecisionCacheEntry {
  const _DecisionCacheEntry({
    required this.action,
    required this.reason,
    required this.matchedRule,
    required this.exceptionRule,
    required this.redirectDataUrl,
    required this.rewrittenUrl,
    required this.candidateCount,
    required this.evaluatedCount,
    required this.expiresAtMs,
  });

  final DecisionAction action;
  final String reason;
  final String? matchedRule;
  final String? exceptionRule;
  final String? redirectDataUrl;
  final String? rewrittenUrl;
  final int candidateCount;
  final int evaluatedCount;
  final int expiresAtMs;
}
