import '../../domain_lock/domain_policy_service.dart';
import '../adblock_engine_bridge.dart';
import '../config/filter_source_manager.dart';
import '../crowd/storage/learned_signature_repository.dart';
import '../filters/filter_compiler.dart';
import '../filters/filter_parser.dart';
import '../injection/scriptlet_engine.dart';
import '../intercept/request_interceptor.dart';
import '../matchers/cosmetic_matcher.dart';
import '../matchers/request_matcher.dart';
import '../utils/tokenize.dart';
import 'adblock_config.dart';
import 'adblock_debug_logger.dart';
import 'adblock_engine.dart';
import 'adblock_metrics.dart';
import 'engine_adapter.dart';
import 'request_blocker.dart';
import 'types.dart';

class AdblockManager {
  factory AdblockManager({
    required DomainPolicyService domainPolicyService,
    required AdblockEngineBridge nativeEngineBridge,
    required AdblockEngineBridge fallbackEngineBridge,
    required AdblockConfig initialConfig,
    LearnedSignatureRepository? learnedSignatureRepository,
  }) {
    final logger = AdblockDebugLogger(enabled: initialConfig.debugMode);
    final metrics = AdblockMetricsCollector();
    final engineAdapter = EngineAdapter(
      nativeEngineBridge: nativeEngineBridge,
      fallbackEngineBridge: fallbackEngineBridge,
      logger: logger,
    );
    final coreEngine = AdblockEngine(
      sourceManager: FilterSourceManager(),
      parser: const FilterParser(),
      compiler: const IndexedFilterCompiler(),
      requestMatcher: const RequestMatcher(),
      cosmeticMatcher: const CosmeticMatcher(),
      scriptletEngine: const ScriptletEngine(),
      requestInterceptor: const RequestInterceptor(),
      bridge: engineAdapter,
      logger: logger,
      domainPolicyService: domainPolicyService,
      metrics: metrics,
      initialConfig: initialConfig,
      learnedSignatureRepository: learnedSignatureRepository,
    );
    final requestBlocker = RequestBlocker(
      domainPolicyService: domainPolicyService,
      logger: logger,
      metrics: metrics,
      learnedSignatureRepository: learnedSignatureRepository,
    )..setConfig(initialConfig);
    return AdblockManager._(
      logger: logger,
      metrics: metrics,
      requestBlocker: requestBlocker,
      coreEngine: coreEngine,
      initialConfig: initialConfig,
      learnedSignatureRepository: learnedSignatureRepository,
    );
  }

  AdblockManager._({
    required AdblockDebugLogger logger,
    required AdblockMetricsCollector metrics,
    required RequestBlocker requestBlocker,
    required AdblockEngine coreEngine,
    required AdblockConfig initialConfig,
    required LearnedSignatureRepository? learnedSignatureRepository,
  }) : _logger = logger,
       _metrics = metrics,
       _requestBlocker = requestBlocker,
       _coreEngine = coreEngine,
       _config = initialConfig,
       _learnedSignatureRepository = learnedSignatureRepository;

  final AdblockDebugLogger _logger;
  final AdblockMetricsCollector _metrics;
  final RequestBlocker _requestBlocker;
  final AdblockEngine _coreEngine;
  final LearnedSignatureRepository? _learnedSignatureRepository;

  AdblockConfig _config;
  Future<void>? _initializeFuture;
  bool _initialized = false;
  bool _disposed = false;
  bool _firstPartyHeuristicProfileLoaded = false;
  String _mainFrameSessionKey = 'none';

  bool get initialized => _initialized;
  bool get enabled => _config.enabled;
  bool get usingNativeEngine => _coreEngine.usingNativeEngine;
  String get activeRevision => _coreEngine.activeRevision;
  int get activeRuleCount => _coreEngine.activeRuleCount;
  List<String> get loadedSources => _coreEngine.loadedSources;
  bool get usedCachedList => _coreEngine.usedCachedList;

  AdblockMetricsSnapshot get metricsSnapshot => _metrics.snapshot();
  EngineStatsSnapshot get engineStatsSnapshot => _coreEngine.getEngineStats();
  Map<String, dynamic> get bridgeDebugSnapshot =>
      _coreEngine.getBridgeDebugSnapshot();

  Future<void> initialize() async {
    if (_disposed) {
      throw StateError('AdblockManager already disposed');
    }
    if (_initialized) {
      return;
    }
    final pending = _initializeFuture;
    if (pending != null) {
      return pending;
    }

    final future = _initializeInternal();
    _initializeFuture = future;
    try {
      await future;
    } finally {
      _initializeFuture = null;
    }
  }

  Future<void> _initializeInternal() async {
    try {
      await _learnedSignatureRepository?.initialize();
    } catch (_) {}

    _requestBlocker.setConfig(_config);
    await _coreEngine.initializeCore(config: _config);
    _firstPartyHeuristicProfileLoaded =
        _coreEngine.firstPartyHeuristicProfileEnabled;
    _requestBlocker.setFirstPartyHeuristicProfile(
      _config.firstPartyHeuristicsEnabled && _firstPartyHeuristicProfileLoaded,
    );
    _requestBlocker.setEngine(_coreEngine);
    _requestBlocker.setConfig(_config);
    _initialized = true;

    _logger.log(
      'manager initialized rules=${_coreEngine.activeRuleCount} revision=${_coreEngine.activeRevision} native=${_coreEngine.usingNativeEngine}',
    );
  }

  Future<AdblockDecision> evaluate(AdblockRequestContext context) async {
    if (_disposed) {
      return const AdblockDecision(blocked: false, reason: 'disposed');
    }
    if (!_initialized) {
      await initialize();
    }
    return _requestBlocker.evaluate(context);
  }

  void onMainFrameChanged(Uri? uri) {
    final nextSessionKey = _sessionKeyFor(uri);
    final shouldResetSessionCache =
        _mainFrameSessionKey != nextSessionKey &&
        _mainFrameSessionKey != 'none' &&
        nextSessionKey != 'none';
    if (shouldResetSessionCache) {
      _requestBlocker.clearCache();
      _logger.log(
        'manager main_frame_session_changed clear_cache from=$_mainFrameSessionKey to=$nextSessionKey',
      );
    }
    _mainFrameSessionKey = nextSessionKey;
    _metrics.onPageChanged(uri);
  }

  void onPlaybackDebugSignal(Map<String, dynamic> payload, {Uri? pageUri}) {
    _requestBlocker.onPlaybackDebugSignal(payload, pageUri: pageUri);
  }

  Future<CosmeticPayload> getCosmeticPayload(Uri? pageUri) async {
    final pageContext = _toPageContext(pageUri);
    if (pageContext == null || _disposed || !_initialized) {
      return CosmeticPayload.empty();
    }
    return _coreEngine.getCosmeticPayload(pageContext);
  }

  Future<ScriptletPayload> getScriptletPayload(Uri? pageUri) async {
    final pageContext = _toPageContext(pageUri);
    if (pageContext == null || _disposed || !_initialized) {
      return ScriptletPayload.empty(runtimeEnabled: _config.enabled);
    }
    return _coreEngine.getScriptletPayload(pageContext);
  }

  Future<AdblockCosmeticResources?> getCosmeticResources(Uri? pageUri) async {
    final cosmeticPayload = await getCosmeticPayload(pageUri);
    final scriptletPayload = await getScriptletPayload(pageUri);
    if (cosmeticPayload.isEmpty && scriptletPayload.isEmpty) {
      return null;
    }
    return AdblockCosmeticResources(
      hideSelectors: cosmeticPayload.hideSelectors,
      proceduralActions: cosmeticPayload.proceduralActions,
      exceptions: cosmeticPayload.exceptions,
      injectedScript: scriptletPayload.scripts.join('\n'),
      generichide: cosmeticPayload.generichide,
    );
  }

  Future<List<String>> getHiddenClassIdSelectors(
    Uri? pageUri, {
    required List<String> classes,
    required List<String> ids,
    Set<String> exceptions = const <String>{},
  }) async {
    if (pageUri == null || pageUri.host.isEmpty) {
      return const <String>[];
    }
    if (_disposed || !_initialized) {
      return const <String>[];
    }
    return _coreEngine.getHiddenClassIdSelectors(
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
    if (_disposed || !_initialized) {
      return null;
    }
    return _coreEngine.getCspDirectives(
      uri,
      resourceType: resourceType,
      sourceUrl: sourceUrl,
    );
  }

  void updateConfig(AdblockConfig config, {bool reinitialize = false}) {
    _config = config;
    _logger.setEnabled(config.debugMode);
    _requestBlocker.setFirstPartyHeuristicProfile(
      _config.firstPartyHeuristicsEnabled && _firstPartyHeuristicProfileLoaded,
    );
    _requestBlocker.setConfig(config);
    _requestBlocker.clearCache();
    if (reinitialize) {
      _initialized = false;
    }
  }

  void setEnabled(bool enabled) {
    if (_config.enabled == enabled) {
      return;
    }
    updateConfig(_config.copyWith(enabled: enabled));
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    try {
      await _learnedSignatureRepository?.dispose();
    } catch (_) {}
    await _coreEngine.dispose();
    _requestBlocker.clearCache();
    _initialized = false;
    _firstPartyHeuristicProfileLoaded = false;
    _mainFrameSessionKey = 'none';
    _logger.reset();
    _metrics.reset();
  }

  String _sessionKeyFor(Uri? uri) {
    if (uri == null) {
      return 'none';
    }
    final host = uri.host.trim().toLowerCase();
    if (host.isEmpty) {
      return 'none';
    }
    final path = uri.path.trim().toLowerCase();
    final normalizedPath = path.isEmpty ? '/' : path;
    final videoId = (uri.queryParameters['v'] ?? '').trim().toLowerCase();
    if (videoId.isNotEmpty) {
      return '$host$normalizedPath?v=$videoId';
    }
    final segments = uri.pathSegments;
    final shortsIndex = segments.indexOf('shorts');
    if (shortsIndex >= 0 && segments.length > shortsIndex + 1) {
      final shortsId = segments[shortsIndex + 1].trim().toLowerCase();
      if (shortsId.isNotEmpty) {
        return '$host/shorts/$shortsId';
      }
    }
    return '$host$normalizedPath';
  }

  PageContext? _toPageContext(Uri? pageUri) {
    if (pageUri == null || pageUri.host.isEmpty) {
      return null;
    }
    final hostname = pageUri.host.toLowerCase();
    return PageContext(
      url: pageUri,
      hostname: hostname,
      domain: registrableDomainFromHost(hostname),
      topLevelUrl: pageUri,
      headers: const <String, String>{},
    );
  }
}
