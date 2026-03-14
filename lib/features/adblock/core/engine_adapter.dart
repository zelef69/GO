import '../adblock_engine_bridge.dart';
import '../models/adblock_rule.dart';
import 'adblock_debug_logger.dart';

class EngineAdapter implements AdblockEngineBridge {
  EngineAdapter({
    required AdblockEngineBridge nativeEngineBridge,
    required AdblockEngineBridge fallbackEngineBridge,
    required AdblockDebugLogger logger,
  }) : _nativeEngineBridge = nativeEngineBridge,
       _fallbackEngineBridge = fallbackEngineBridge,
       _logger = logger;

  final AdblockEngineBridge _nativeEngineBridge;
  final AdblockEngineBridge _fallbackEngineBridge;
  final AdblockDebugLogger _logger;

  bool _initialized = false;
  bool _fallbackInitialized = false;
  bool _usingNativeEngine = false;
  late AdblockEngineBridge _activeEngine;
  int _nativeInitSuccessCount = 0;
  int _nativeInitFailureCount = 0;
  int _fallbackInitSuccessCount = 0;
  int _fallbackInitFailureCount = 0;
  int _evaluateRequestCallCount = 0;
  int _nativeEvaluateCallCount = 0;
  int _fallbackEvaluateCallCount = 0;

  bool get initialized => _initialized;
  bool get usingNativeEngine => _usingNativeEngine;

  Map<String, dynamic> get debugSnapshot => <String, dynamic>{
    'initialized': _initialized,
    'usingNativeEngine': _usingNativeEngine,
    'nativeInitSuccessCount': _nativeInitSuccessCount,
    'nativeInitFailureCount': _nativeInitFailureCount,
    'fallbackInitSuccessCount': _fallbackInitSuccessCount,
    'fallbackInitFailureCount': _fallbackInitFailureCount,
    'evaluateRequestCallCount': _evaluateRequestCallCount,
    'nativeEvaluateCallCount': _nativeEvaluateCallCount,
    'fallbackEvaluateCallCount': _fallbackEvaluateCallCount,
  };

  Future<bool> isNativeEngineAvailable() => _nativeEngineBridge.isAvailable();

  @override
  Future<bool> isAvailable() async {
    final nativeAvailable = await _nativeEngineBridge.isAvailable();
    if (nativeAvailable) {
      return true;
    }
    return _fallbackEngineBridge.isAvailable();
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
    if (_initialized) {
      _logger.log('engine adapter reinitialize requested');
      await dispose();
    }

    final isNativeAvailable = await _nativeEngineBridge.isAvailable();
    if (isNativeAvailable) {
      try {
        await _nativeEngineBridge.initialize(
          rules,
          rawFilterText: rawFilterText,
          resourcesJson: resourcesJson,
          catalogSourcesJson: catalogSourcesJson,
          serializedEngineBase64: serializedEngineBase64,
          enabledTags: enabledTags,
        );
        _activeEngine = _nativeEngineBridge;
        _usingNativeEngine = true;
        _nativeInitSuccessCount += 1;
        _initialized = true;
        _logger.log('engine adapter selected native');
        return;
      } catch (_) {
        _nativeInitFailureCount += 1;
        _logger.log('engine adapter native init failed');
      }
    }

    if (rules.isEmpty) {
      throw StateError('Fallback engine requires compiled rules');
    }

    try {
      await _fallbackEngineBridge.initialize(
        rules,
        rawFilterText: rawFilterText,
        resourcesJson: resourcesJson,
        catalogSourcesJson: catalogSourcesJson,
        serializedEngineBase64: serializedEngineBase64,
        enabledTags: enabledTags,
      );
      _fallbackInitialized = true;
      _fallbackInitSuccessCount += 1;
    } catch (_) {
      _fallbackInitFailureCount += 1;
      _logger.log('engine adapter fallback init failed');
    }

    if (_fallbackInitialized) {
      _activeEngine = _fallbackEngineBridge;
      _usingNativeEngine = false;
      _initialized = true;
      _logger.log('engine adapter selected fallback');
      return;
    }

    throw StateError('Adblock engines failed to initialize');
  }

  @override
  Future<bool> shouldBlock(
    Uri uri, {
    required String resourceType,
    Uri? sourceUrl,
  }) async {
    if (!_initialized) {
      return false;
    }
    return _activeEngine.shouldBlock(
      uri,
      resourceType: resourceType,
      sourceUrl: sourceUrl,
    );
  }

  @override
  Future<AdblockEngineRequestResult> evaluateRequestDetailed(
    Uri uri, {
    required String resourceType,
    Uri? sourceUrl,
  }) async {
    if (!_initialized) {
      return AdblockEngineRequestResult.allow();
    }
    _evaluateRequestCallCount += 1;
    if (_usingNativeEngine) {
      _nativeEvaluateCallCount += 1;
    } else {
      _fallbackEvaluateCallCount += 1;
    }
    return _activeEngine.evaluateRequestDetailed(
      uri,
      resourceType: resourceType,
      sourceUrl: sourceUrl,
    );
  }

  @override
  Future<AdblockCosmeticResources?> getCosmeticResources(Uri pageUri) async {
    if (!_initialized) {
      return null;
    }
    try {
      return await _activeEngine.getCosmeticResources(pageUri);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<String>> getHiddenClassIdSelectors(
    Uri pageUri, {
    required List<String> classes,
    required List<String> ids,
    Set<String> exceptions = const <String>{},
  }) async {
    if (!_initialized) {
      return const <String>[];
    }
    return _activeEngine.getHiddenClassIdSelectors(
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
    if (!_initialized) {
      return null;
    }
    return _activeEngine.getCspDirectives(
      uri,
      resourceType: resourceType,
      sourceUrl: sourceUrl,
    );
  }

  @override
  Future<String?> serializeEngine() async {
    if (!_initialized) {
      return null;
    }
    return _activeEngine.serializeEngine();
  }

  @override
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
    _activeEngine = _fallbackEngineBridge;
  }

  Future<void> _safeDispose(AdblockEngineBridge engine) async {
    try {
      await engine.dispose();
    } catch (_) {}
  }
}
