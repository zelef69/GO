import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../domain_lock/domain_policy_service.dart';
import 'adblock_engine_bridge.dart';
import 'core/adblock_config.dart';
import 'core/adblock_debug_logger.dart';
import 'core/adblock_manager.dart';
import 'core/cosmetic_filter_injector.dart';
import 'core/request_blocker.dart';
import 'core/scriptlet_injector.dart';
import 'core/webview_integration.dart';

class AdblockService {
  AdblockService({
    required DomainPolicyService domainPolicyService,
    required AdblockEngineBridge nativeEngineBridge,
    required AdblockEngineBridge fallbackEngineBridge,
    required bool enabled,
  }) : _config = AdblockConfig.defaults(
         enabled: enabled,
         debugMode: kDebugMode,
       ),
       _logger = AdblockDebugLogger(enabled: kDebugMode),
       _manager = AdblockManager(
         domainPolicyService: domainPolicyService,
         nativeEngineBridge: nativeEngineBridge,
         fallbackEngineBridge: fallbackEngineBridge,
         initialConfig: AdblockConfig.defaults(
           enabled: enabled,
           debugMode: kDebugMode,
         ),
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
  }

  final AdblockDebugLogger _logger;
  final AdblockManager _manager;
  final CosmeticFilterInjector _cosmeticFilterInjector;
  final ScriptletInjector _scriptletInjector;
  late final WebViewAdblockIntegration _webViewIntegration;

  AdblockConfig _config;
  bool _initialized = false;
  int _debugBlockLogCount = 0;
  static const int _maxDebugBlockLogs = 120;

  bool get enabled => _config.enabled;
  bool get usingNativeEngine => _manager.usingNativeEngine;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    await _manager.initialize();
    _initialized = true;
    _logger.log(
      'service initialized native=${_manager.usingNativeEngine} rules=${_manager.activeRuleCount} revision=${_manager.activeRevision}',
    );
  }

  void setEnabled(bool enabled) {
    if (_config.enabled == enabled) {
      return;
    }
    _config = _config.copyWith(enabled: enabled);
    _manager.setEnabled(enabled);
    _webViewIntegration.updateConfig(_config);
    _logger.log('service setEnabled=$enabled');
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

  Future<AdblockDecision> evaluateRequest(
    Uri uri, {
    required String resourceType,
    Uri? sourceUrl,
    bool fromServiceWorker = false,
  }) async {
    if (!_config.enabled) {
      return const AdblockDecision(blocked: false, reason: 'disabled');
    }
    final decision = await _webViewIntegration.evaluateRequest(
      uri: uri,
      resourceType: resourceType,
      sourceUri: sourceUrl,
      fromServiceWorker: fromServiceWorker,
    );
    if (decision.blocked && _debugBlockLogCount < _maxDebugBlockLogs) {
      _debugBlockLogCount += 1;
      _logger.log(
        'blocked host=${uri.host} path=${uri.path} type=$resourceType reason=${decision.reason} cache=${decision.fromCache}',
      );
    }
    return decision;
  }

  Future<bool> shouldBlockRequest(
    Uri? uri, {
    required String resourceType,
    Uri? sourceUrl,
  }) async {
    if (uri == null) {
      return false;
    }
    final decision = await evaluateRequest(
      uri,
      resourceType: resourceType,
      sourceUrl: sourceUrl,
    );
    return decision.blocked;
  }

  Future<void> dispose() async {
    await _webViewIntegration.dispose();
    await _manager.dispose();
    _initialized = false;
    _debugBlockLogCount = 0;
  }
}
