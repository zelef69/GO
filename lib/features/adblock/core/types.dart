class RequestContext {
  const RequestContext({
    required this.url,
    required this.hostname,
    required this.domain,
    required this.path,
    required this.query,
    required this.resourceType,
    required this.frameUrl,
    required this.topLevelUrl,
    required this.frameHostname,
    required this.topLevelHostname,
    required this.method,
    required this.headers,
    required this.isThirdParty,
    required this.isTopLevel,
  });

  final Uri url;
  final String hostname;
  final String domain;
  final String path;
  final String query;
  final String resourceType;
  final Uri? frameUrl;
  final Uri? topLevelUrl;
  final String frameHostname;
  final String topLevelHostname;
  final String method;
  final Map<String, String> headers;
  final bool isThirdParty;
  final bool isTopLevel;
}

class PageContext {
  const PageContext({
    required this.url,
    required this.hostname,
    required this.domain,
    required this.topLevelUrl,
    required this.headers,
  });

  final Uri url;
  final String hostname;
  final String domain;
  final Uri? topLevelUrl;
  final Map<String, String> headers;
}

enum DecisionAction { allow, block, redirect, rewriteResponse }

class RequestDecision {
  const RequestDecision({
    required this.action,
    required this.reason,
    this.matchedRule,
    this.exceptionRule,
    this.redirectDataUrl,
    this.rewrittenUrl,
    this.fromCache = false,
    this.candidateCount = 0,
    this.evaluatedCount = 0,
  });

  factory RequestDecision.allow({
    String reason = 'allow',
    String? exceptionRule,
    bool fromCache = false,
    int candidateCount = 0,
    int evaluatedCount = 0,
  }) {
    return RequestDecision(
      action: DecisionAction.allow,
      reason: reason,
      exceptionRule: exceptionRule,
      fromCache: fromCache,
      candidateCount: candidateCount,
      evaluatedCount: evaluatedCount,
    );
  }

  factory RequestDecision.block({
    String reason = 'block',
    String? matchedRule,
    bool fromCache = false,
    int candidateCount = 0,
    int evaluatedCount = 0,
  }) {
    return RequestDecision(
      action: DecisionAction.block,
      reason: reason,
      matchedRule: matchedRule,
      fromCache: fromCache,
      candidateCount: candidateCount,
      evaluatedCount: evaluatedCount,
    );
  }

  factory RequestDecision.redirect({
    required String reason,
    required String redirectDataUrl,
    String? matchedRule,
    bool fromCache = false,
    int candidateCount = 0,
    int evaluatedCount = 0,
  }) {
    return RequestDecision(
      action: DecisionAction.redirect,
      reason: reason,
      matchedRule: matchedRule,
      redirectDataUrl: redirectDataUrl,
      fromCache: fromCache,
      candidateCount: candidateCount,
      evaluatedCount: evaluatedCount,
    );
  }

  factory RequestDecision.rewriteResponse({
    required String reason,
    required String rewrittenUrl,
    String? matchedRule,
    bool fromCache = false,
    int candidateCount = 0,
    int evaluatedCount = 0,
  }) {
    return RequestDecision(
      action: DecisionAction.rewriteResponse,
      reason: reason,
      matchedRule: matchedRule,
      rewrittenUrl: rewrittenUrl,
      fromCache: fromCache,
      candidateCount: candidateCount,
      evaluatedCount: evaluatedCount,
    );
  }

  final DecisionAction action;
  final String reason;
  final String? matchedRule;
  final String? exceptionRule;
  final String? redirectDataUrl;
  final String? rewrittenUrl;
  final bool fromCache;
  final int candidateCount;
  final int evaluatedCount;

  bool get blocked =>
      action == DecisionAction.block || action == DecisionAction.redirect;
}

class NetworkMatchDecision {
  const NetworkMatchDecision({
    required this.blocked,
    required this.reason,
    this.action = DecisionAction.allow,
    this.matchedRule,
    this.exceptionRule,
    this.redirectDataUrl,
    this.rewrittenUrl,
    this.candidateCount = 0,
    this.evaluatedCount = 0,
    this.usedRegexFallback = false,
  });

  factory NetworkMatchDecision.allow({
    String reason = 'allow',
    String? exceptionRule,
    int candidateCount = 0,
    int evaluatedCount = 0,
    bool usedRegexFallback = false,
  }) {
    return NetworkMatchDecision(
      blocked: false,
      reason: reason,
      action: DecisionAction.allow,
      exceptionRule: exceptionRule,
      candidateCount: candidateCount,
      evaluatedCount: evaluatedCount,
      usedRegexFallback: usedRegexFallback,
    );
  }

  final bool blocked;
  final String reason;
  final DecisionAction action;
  final String? matchedRule;
  final String? exceptionRule;
  final String? redirectDataUrl;
  final String? rewrittenUrl;
  final int candidateCount;
  final int evaluatedCount;
  final bool usedRegexFallback;
}

class CosmeticRules {
  const CosmeticRules({
    required this.selectors,
    required this.exceptions,
    required this.generichide,
  });

  factory CosmeticRules.empty() {
    return const CosmeticRules(
      selectors: <String>{},
      exceptions: <String>{},
      generichide: false,
    );
  }

  final Set<String> selectors;
  final Set<String> exceptions;
  final bool generichide;
}

class InjectionScripts {
  const InjectionScripts({required this.scripts});

  factory InjectionScripts.empty() {
    return const InjectionScripts(scripts: <String>[]);
  }

  final List<String> scripts;
}

class CosmeticPayload {
  const CosmeticPayload({
    required this.hideSelectors,
    required this.proceduralActions,
    required this.exceptions,
    required this.generichide,
  });

  factory CosmeticPayload.empty() {
    return const CosmeticPayload(
      hideSelectors: <String>{},
      proceduralActions: <String>{},
      exceptions: <String>{},
      generichide: false,
    );
  }

  final Set<String> hideSelectors;
  final Set<String> proceduralActions;
  final Set<String> exceptions;
  final bool generichide;

  bool get isEmpty =>
      hideSelectors.isEmpty &&
      proceduralActions.isEmpty &&
      exceptions.isEmpty &&
      !generichide;
}

class ScriptletPayload {
  const ScriptletPayload({required this.scripts, required this.runtimeEnabled});

  factory ScriptletPayload.empty({bool runtimeEnabled = true}) {
    return ScriptletPayload(
      scripts: const <String>[],
      runtimeEnabled: runtimeEnabled,
    );
  }

  final List<String> scripts;
  final bool runtimeEnabled;

  bool get isEmpty => scripts.isEmpty;
}

class FilterListMetadata {
  const FilterListMetadata({
    required this.id,
    required this.title,
    required this.version,
    required this.enabled,
    required this.updatedAtMs,
    required this.source,
  });

  final String id;
  final String title;
  final String version;
  final bool enabled;
  final int updatedAtMs;
  final String source;
}

class FilterSourceSnapshot {
  const FilterSourceSnapshot({
    required this.lines,
    required this.rawFilterText,
    required this.loadedSources,
    required this.usedCachedData,
    required this.resourcesJson,
    required this.enabledTags,
    required this.catalogSourcesJson,
    required this.serializedEngineBase64,
    required this.engineSnapshotKey,
    required this.firstPartyHeuristicsProfileEnabled,
    required this.metadata,
  });

  final List<String> lines;
  final String rawFilterText;
  final List<String> loadedSources;
  final bool usedCachedData;
  final String resourcesJson;
  final List<String> enabledTags;
  final String catalogSourcesJson;
  final String serializedEngineBase64;
  final String engineSnapshotKey;
  final bool firstPartyHeuristicsProfileEnabled;
  final List<FilterListMetadata> metadata;
}

class FilterSourceRegistry {
  const FilterSourceRegistry({required this.metadata});

  final List<FilterListMetadata> metadata;

  Map<String, FilterListMetadata> byId() {
    final map = <String, FilterListMetadata>{};
    for (final entry in metadata) {
      map[entry.id] = entry;
    }
    return map;
  }
}

class EngineStatsSnapshot {
  const EngineStatsSnapshot({
    required this.totalRequestEvaluations,
    required this.decisionCacheHits,
    required this.decisionCacheMisses,
    required this.regexFallbackCount,
    required this.allowDecisionCount,
    required this.blockDecisionCount,
    required this.redirectDecisionCount,
    required this.rewriteDecisionCount,
    required this.bridgeEvaluationCount,
    required this.bridgeErrorCount,
    required this.bridgeAllowCount,
    required this.bridgeBlockCount,
    required this.bridgeRedirectCount,
    required this.bridgeRewriteCount,
    required this.bridgeFallbackCount,
    required this.candidateTotalCount,
    required this.evaluatedTotalCount,
    required this.maxCandidateCount,
    required this.maxEvaluatedCount,
    required this.lastNormalizationMicros,
    required this.lastCandidateLookupMicros,
    required this.lastCandidateEvaluationMicros,
    required this.lastBridgeEvaluationMicros,
    required this.lastCompileDurationMs,
    required this.compileCount,
    required this.lastCompiledNetworkRuleCount,
    required this.lastCompiledCosmeticRuleCount,
    required this.lastCompiledScriptletRuleCount,
    required this.lastCosmeticPayloadSize,
    required this.lastScriptletPayloadSize,
  });

  factory EngineStatsSnapshot.empty() {
    return const EngineStatsSnapshot(
      totalRequestEvaluations: 0,
      decisionCacheHits: 0,
      decisionCacheMisses: 0,
      regexFallbackCount: 0,
      allowDecisionCount: 0,
      blockDecisionCount: 0,
      redirectDecisionCount: 0,
      rewriteDecisionCount: 0,
      bridgeEvaluationCount: 0,
      bridgeErrorCount: 0,
      bridgeAllowCount: 0,
      bridgeBlockCount: 0,
      bridgeRedirectCount: 0,
      bridgeRewriteCount: 0,
      bridgeFallbackCount: 0,
      candidateTotalCount: 0,
      evaluatedTotalCount: 0,
      maxCandidateCount: 0,
      maxEvaluatedCount: 0,
      lastNormalizationMicros: 0,
      lastCandidateLookupMicros: 0,
      lastCandidateEvaluationMicros: 0,
      lastBridgeEvaluationMicros: 0,
      lastCompileDurationMs: 0,
      compileCount: 0,
      lastCompiledNetworkRuleCount: 0,
      lastCompiledCosmeticRuleCount: 0,
      lastCompiledScriptletRuleCount: 0,
      lastCosmeticPayloadSize: 0,
      lastScriptletPayloadSize: 0,
    );
  }

  final int totalRequestEvaluations;
  final int decisionCacheHits;
  final int decisionCacheMisses;
  final int regexFallbackCount;
  final int allowDecisionCount;
  final int blockDecisionCount;
  final int redirectDecisionCount;
  final int rewriteDecisionCount;
  final int bridgeEvaluationCount;
  final int bridgeErrorCount;
  final int bridgeAllowCount;
  final int bridgeBlockCount;
  final int bridgeRedirectCount;
  final int bridgeRewriteCount;
  final int bridgeFallbackCount;
  final int candidateTotalCount;
  final int evaluatedTotalCount;
  final int maxCandidateCount;
  final int maxEvaluatedCount;
  final int lastNormalizationMicros;
  final int lastCandidateLookupMicros;
  final int lastCandidateEvaluationMicros;
  final int lastBridgeEvaluationMicros;
  final int lastCompileDurationMs;
  final int compileCount;
  final int lastCompiledNetworkRuleCount;
  final int lastCompiledCosmeticRuleCount;
  final int lastCompiledScriptletRuleCount;
  final int lastCosmeticPayloadSize;
  final int lastScriptletPayloadSize;

  int get cacheRequestCount => decisionCacheHits + decisionCacheMisses;

  double get decisionCacheHitRate {
    final total = cacheRequestCount;
    if (total == 0) {
      return 0;
    }
    return decisionCacheHits / total;
  }

  int get decisionCountTotal =>
      allowDecisionCount +
      blockDecisionCount +
      redirectDecisionCount +
      rewriteDecisionCount;

  double get averageCandidateCount {
    final total = decisionCountTotal;
    if (total == 0) {
      return 0;
    }
    return candidateTotalCount / total;
  }

  double get averageEvaluatedCount {
    final total = decisionCountTotal;
    if (total == 0) {
      return 0;
    }
    return evaluatedTotalCount / total;
  }
}

abstract interface class AdblockRuntimeEngine {
  Future<RequestDecision> evaluateRequest(RequestContext context);

  Future<CosmeticPayload> getCosmeticPayload(PageContext pageContext);

  Future<ScriptletPayload> getScriptletPayload(PageContext pageContext);
}

abstract interface class RequestNormalizationObserver {
  void recordRequestNormalizationMicros(int micros);
}
