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

  bool get initialized => _initialized;
  bool get usingNativeEngine => _usingNativeEngine;

  @override
  Future<bool> isAvailable() async {
    final nativeAvailable = await _nativeEngineBridge.isAvailable();
    if (nativeAvailable) {
      return true;
    }
    return _fallbackEngineBridge.isAvailable();
  }

  @override
  Future<void> initialize(List<AdblockRule> rules) async {
    if (_initialized) {
      return;
    }

    try {
      await _fallbackEngineBridge.initialize(rules);
      _fallbackInitialized = true;
    } catch (_) {
      _logger.log('engine adapter fallback init failed');
    }

    final isNativeAvailable = await _nativeEngineBridge.isAvailable();
    if (isNativeAvailable) {
      try {
        await _nativeEngineBridge.initialize(rules);
        _activeEngine = _nativeEngineBridge;
        _usingNativeEngine = true;
        _initialized = true;
        _logger.log('engine adapter selected native');
        return;
      } catch (_) {
        _logger.log('engine adapter native init failed, using fallback');
      }
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
