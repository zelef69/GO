import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../domain_lock/domain_policy_service.dart';
import 'adblock_engine_bridge.dart';
import 'crowd/storage/learned_signature_repository.dart';
import 'crowd/sync/crowd_sync_service.dart';
import 'core/adblock_config.dart';
import 'core/adblock_debug_logger.dart';
import 'core/adblock_manager.dart';
import 'core/adblock_metrics.dart';
import 'core/cosmetic_filter_injector.dart';
import 'core/request_blocker.dart';
import 'core/scriptlet_injector.dart';
import 'core/types.dart';
import 'core/webview_integration.dart';

class AdblockService {
  AdblockService({
    required DomainPolicyService domainPolicyService,
    required AdblockEngineBridge nativeEngineBridge,
    required AdblockEngineBridge fallbackEngineBridge,
    required bool enabled,
    LearnedSignatureRepository? learnedSignatureRepository,
    CrowdSyncService? crowdSyncService,
  }) : _config = AdblockConfig.defaults(
         enabled: enabled,
         debugMode: kDebugMode,
       ),
       _learnedSignatureRepository = learnedSignatureRepository,
       _crowdSyncService = crowdSyncService,
       _logger = AdblockDebugLogger(enabled: kDebugMode),
       _manager = AdblockManager(
         domainPolicyService: domainPolicyService,
         nativeEngineBridge: nativeEngineBridge,
         fallbackEngineBridge: fallbackEngineBridge,
         initialConfig: AdblockConfig.defaults(
           enabled: enabled,
           debugMode: kDebugMode,
         ),
         learnedSignatureRepository: learnedSignatureRepository,
       ),
       _cosmeticFilterInjector = CosmeticFilterInjector(
         logger: AdblockDebugLogger(enabled: kDebugMode),
       ),
       _scriptletInjector = ScriptletInjector(
         logger: AdblockDebugLogger(enabled: kDebugMode),
       ) {
    _webViewIntegration = WebViewAdblockIntegration(
      manager: _manager,
      logger: _logger,
      cosmeticFilterInjector: _cosmeticFilterInjector,
      scriptletInjector: _scriptletInjector,
      initialConfig: _config,
    );
    _crowdSyncService?.updateFlags(
      crowdLearningEnabled: _config.crowdLearningEnabled,
      crowdSyncEnabled: _config.crowdSyncEnabled,
    );
  }

  final LearnedSignatureRepository? _learnedSignatureRepository;
  final CrowdSyncService? _crowdSyncService;
  final AdblockDebugLogger _logger;
  final AdblockManager _manager;
  final CosmeticFilterInjector _cosmeticFilterInjector;
  final ScriptletInjector _scriptletInjector;
  late final WebViewAdblockIntegration _webViewIntegration;

  AdblockConfig _config;
  bool _initialized = false;
  int _debugBlockLogCount = 0;
  static const int _maxDebugBlockLogs = 120;
  int _debugDecisionLogCount = 0;
  static const int _maxDebugDecisionLogs = 600;

  bool get enabled => _config.enabled;
  bool get usingNativeEngine => _manager.usingNativeEngine;
  AdblockMetricsSnapshot get metricsSnapshot => _manager.metricsSnapshot;
  EngineStatsSnapshot get engineStatsSnapshot => _manager.engineStatsSnapshot;

  Map<String, dynamic> getDebugSnapshot() {
    final metrics = metricsSnapshot;
    final engineStats = engineStatsSnapshot;
    return <String, dynamic>{
      'enabled': _config.enabled,
      'usingNativeEngine': usingNativeEngine,
      'runtime': <String, dynamic>{
        'blockedRequests': metrics.blockedRequests,
        'allowedRequests': metrics.allowedRequests,
        'lastMatchedRule': metrics.lastMatchedRule,
        'lastDecisionReason': metrics.lastDecisionReason,
        'lastEvaluationMs': metrics.lastEvaluationMs,
        'currentPageHost': metrics.currentPageHost,
        'pageBlockedRequests': metrics.pageBlockedRequests,
        'pageAllowedRequests': metrics.pageAllowedRequests,
      },
      'engine': <String, dynamic>{
        'totalRequestEvaluations': engineStats.totalRequestEvaluations,
        'decisionCacheHits': engineStats.decisionCacheHits,
        'decisionCacheMisses': engineStats.decisionCacheMisses,
        'decisionCacheHitRate': engineStats.decisionCacheHitRate,
        'regexFallbackCount': engineStats.regexFallbackCount,
        'allowDecisionCount': engineStats.allowDecisionCount,
        'blockDecisionCount': engineStats.blockDecisionCount,
        'redirectDecisionCount': engineStats.redirectDecisionCount,
        'rewriteDecisionCount': engineStats.rewriteDecisionCount,
        'bridgeEvaluationCount': engineStats.bridgeEvaluationCount,
        'bridgeFallbackCount': engineStats.bridgeFallbackCount,
        'bridgeErrorCount': engineStats.bridgeErrorCount,
        'bridgeAllowCount': engineStats.bridgeAllowCount,
        'bridgeBlockCount': engineStats.bridgeBlockCount,
        'bridgeRedirectCount': engineStats.bridgeRedirectCount,
        'bridgeRewriteCount': engineStats.bridgeRewriteCount,
        'candidateTotalCount': engineStats.candidateTotalCount,
        'evaluatedTotalCount': engineStats.evaluatedTotalCount,
        'maxCandidateCount': engineStats.maxCandidateCount,
        'maxEvaluatedCount': engineStats.maxEvaluatedCount,
        'averageCandidateCount': engineStats.averageCandidateCount,
        'averageEvaluatedCount': engineStats.averageEvaluatedCount,
        'lastNormalizationMicros': engineStats.lastNormalizationMicros,
        'lastCandidateLookupMicros': engineStats.lastCandidateLookupMicros,
        'lastCandidateEvaluationMicros':
            engineStats.lastCandidateEvaluationMicros,
        'lastBridgeEvaluationMicros': engineStats.lastBridgeEvaluationMicros,
        'lastCompileDurationMs': engineStats.lastCompileDurationMs,
        'compileCount': engineStats.compileCount,
        'lastCompiledNetworkRuleCount':
            engineStats.lastCompiledNetworkRuleCount,
        'lastCompiledCosmeticRuleCount':
            engineStats.lastCompiledCosmeticRuleCount,
        'lastCompiledScriptletRuleCount':
            engineStats.lastCompiledScriptletRuleCount,
        'lastCosmeticPayloadSize': engineStats.lastCosmeticPayloadSize,
        'lastScriptletPayloadSize': engineStats.lastScriptletPayloadSize,
      },
      'injectors': <String, dynamic>{
        'cosmetic': _cosmeticFilterInjector.debugSnapshot,
        'scriptlet': _scriptletInjector.debugSnapshot,
      },
      'bridge': _manager.bridgeDebugSnapshot,
      'webview': _webViewIntegration.debugSnapshot,
    };
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    try {
      await _learnedSignatureRepository?.initialize();
    } catch (_) {}
    await _manager.initialize();
    try {
      await _crowdSyncService?.initialize();
    } catch (_) {}
    _crowdSyncService?.scheduleSync(reason: 'adblock_initialize');
    _initialized = true;
    _logger.log(
      'บริการบล็อกโฆษณาเริ่มทำงานแล้ว native=${_manager.usingNativeEngine} จำนวนกฎ=${_manager.activeRuleCount} revision=${_manager.activeRevision}',
    );
  }

  void setEnabled(bool enabled) {
    if (_config.enabled == enabled) {
      return;
    }
    _config = _config.copyWith(enabled: enabled);
    _manager.setEnabled(enabled);
    _webViewIntegration.updateConfig(_config);
    _crowdSyncService?.updateFlags(
      crowdLearningEnabled: _config.crowdLearningEnabled,
      crowdSyncEnabled: _config.crowdSyncEnabled,
    );
    _logger.log('สลับสถานะบริการบล็อกโฆษณา enabled=$enabled');
  }

  Future<void> attachWebView(InAppWebViewController controller) async {
    await _webViewIntegration.attachWebView(controller);
  }

  void onMainFrameChanged(Uri? uri) {
    _webViewIntegration.onMainFrameChanged(uri);
  }

  Future<void> onPageStarted(Uri? uri) async {
    await _webViewIntegration.onPageStarted(uri);
  }

  Future<void> onPageFinished(Uri? uri) async {
    await _webViewIntegration.onPageFinished(uri);
  }

  Future<void> syncRuntimeLayers({bool force = false}) async {
    await _webViewIntegration.syncRuntimeLayers(force: force);
  }

  Future<void> onAppResumed() async {
    await _webViewIntegration.ensureInterceptionAttached(reason: 'app_resumed');
  }

  Future<List<String>> getHiddenClassIdSelectors(
    Uri pageUri, {
    required List<String> classes,
    required List<String> ids,
    Set<String> exceptions = const <String>{},
  }) async {
    if (!_initialized) {
      await initialize();
    }
    return _manager.getHiddenClassIdSelectors(
      pageUri,
      classes: classes,
      ids: ids,
      exceptions: exceptions,
    );
  }

  Future<String?> getCspDirectives(
    Uri uri, {
    required String resourceType,
    Uri? sourceUrl,
  }) async {
    if (!_initialized) {
      await initialize();
    }
    return _manager.getCspDirectives(
      uri,
      resourceType: resourceType,
      sourceUrl: sourceUrl,
    );
  }

  Future<AdblockDecision> evaluateRequest(
    Uri uri, {
    required String resourceType,
    Uri? sourceUrl,
    bool fromServiceWorker = false,
    bool? adShowing,
    bool? playbackStalled,
    String? adSignalKey,
  }) async {
    if (!_config.enabled) {
      return const AdblockDecision(blocked: false, reason: 'disabled');
    }
    final startedAtMs = DateTime.now().millisecondsSinceEpoch;
    final decision = await _webViewIntegration.evaluateRequest(
      uri: uri,
      resourceType: resourceType,
      sourceUri: sourceUrl,
      fromServiceWorker: fromServiceWorker,
      adShowing: adShowing,
      playbackStalled: playbackStalled,
      adSignalKey: adSignalKey,
    );
    if (decision.blocked && _debugBlockLogCount < _maxDebugBlockLogs) {
      _debugBlockLogCount += 1;
      _logger.log(
        'blocked host=${uri.host} path=${uri.path} type=$resourceType reason=${decision.reason} cache=${decision.fromCache}',
      );
    }
    if (_config.debugMode && _debugDecisionLogCount < _maxDebugDecisionLogs) {
      _debugDecisionLogCount += 1;
      final sourceSummary = sourceUrl == null
          ? 'none'
          : '${sourceUrl.host}${sourceUrl.path.isEmpty ? '/' : sourceUrl.path}';
      final elapsedMs = DateTime.now().millisecondsSinceEpoch - startedAtMs;
      _logger.log(
        'สรุปการประเมินคำขอบล็อกโฆษณา host=${uri.host} path=${uri.path} type=$resourceType blocked=${decision.blocked} reason=${decision.reason} cache=${decision.fromCache} sw=$fromServiceWorker adShowing=${adShowing ?? false} stalled=${playbackStalled ?? false} signal=${adSignalKey ?? 'auto'} source=$sourceSummary ใช้เวลาMs=$elapsedMs',
      );
    }
    return decision;
  }

  Future<bool> shouldBlockRequest(
    Uri? uri, {
    required String resourceType,
    Uri? sourceUrl,
    bool adShowing = false,
  }) async {
    if (uri == null) {
      return false;
    }
    final decision = await evaluateRequest(
      uri,
      resourceType: resourceType,
      sourceUrl: sourceUrl,
      adShowing: adShowing,
    );
    return decision.blocked;
  }

  String resolveRequestSignalKey(Uri uri, {Uri? sourceUrl}) {
    return _webViewIntegration.resolveRequestSignalKey(
      uri,
      sourceUri: sourceUrl,
    );
  }

  bool isAdSignalActiveForRequest(Uri uri, {Uri? sourceUrl}) {
    return _webViewIntegration.isAdSignalActiveForRequest(
      uri,
      sourceUri: sourceUrl,
    );
  }

  bool isPlaybackStalledForRequest(Uri uri, {Uri? sourceUrl}) {
    return _webViewIntegration.isPlaybackStalledForRequest(
      uri,
      sourceUri: sourceUrl,
    );
  }

  void onPlaybackDebugSignal(Map<String, dynamic> payload, {Uri? pageUri}) {
    _webViewIntegration.updatePlaybackDebugSignal(payload, pageUri: pageUri);
  }

  void onAdblockDebugSignal(Map<String, dynamic> payload, {Uri? pageUri}) {
    _webViewIntegration.updateAdblockDebugSignal(payload, pageUri: pageUri);
  }

  void scheduleCrowdSync({required String reason}) {
    if (!_config.crowdLearningEnabled || !_config.crowdSyncEnabled) {
      return;
    }
    _crowdSyncService?.scheduleSync(reason: reason);
  }

  Future<void> syncCrowdNow({
    required String reason,
    bool force = false,
  }) async {
    if (!_config.crowdLearningEnabled || !_config.crowdSyncEnabled) {
      return;
    }
    await _crowdSyncService?.syncNow(reason: reason, force: force);
  }

  Future<void> dispose() async {
    await _crowdSyncService?.dispose();
    await _webViewIntegration.dispose();
    await _manager.dispose();
    _initialized = false;
    _debugBlockLogCount = 0;
    _debugDecisionLogCount = 0;
  }
}
