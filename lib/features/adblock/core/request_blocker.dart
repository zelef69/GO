import '../../domain_lock/domain_policy_service.dart';
import '../crowd/storage/learned_signature_repository.dart';
import '../intercept/request_interceptor.dart';
import 'adblock_config.dart';
import 'adblock_debug_logger.dart';
import 'adblock_metrics.dart';
import 'adblock_request_runtime_engine.dart';
import 'engine_request_policy.dart';
import 'request_runtime_models.dart';
import 'types.dart';

export 'request_runtime_models.dart';

class RequestBlocker {
  RequestBlocker({
    required DomainPolicyService domainPolicyService,
    required AdblockDebugLogger logger,
    required AdblockMetricsCollector metrics,
    LearnedSignatureRepository? learnedSignatureRepository,
    RequestInterceptor requestInterceptor = const RequestInterceptor(),
  }) : _policy = EngineRequestPolicy(
         domainPolicyService: domainPolicyService,
         logger: logger,
         metrics: metrics,
         learnedSignatureRepository: learnedSignatureRepository,
         requestInterceptor: requestInterceptor,
       );

  final EngineRequestPolicy _policy;
  AdblockRequestRuntimeEngine? _runtimeEngine;

  void setConfig(AdblockConfig config) {
    _policy.setConfig(config);
    _runtimeEngine?.setRuntimeConfig(config);
  }

  void setEngine(AdblockRuntimeEngine engine) {
    _policy.setEngine(engine);
    _runtimeEngine = engine is AdblockRequestRuntimeEngine ? engine : null;
  }

  void setFirstPartyHeuristicProfile(bool enabled) {
    _policy.setFirstPartyHeuristicProfile(enabled);
    _runtimeEngine?.setFirstPartyHeuristicProfile(enabled);
  }

  void clearCache() {
    _policy.clearCache();
    _runtimeEngine?.clearRuntimeCache();
  }

  void onPlaybackDebugSignal(Map<String, dynamic> payload, {Uri? pageUri}) {
    final runtimeEngine = _runtimeEngine;
    if (runtimeEngine != null) {
      runtimeEngine.onPlaybackDebugSignal(payload, pageUri: pageUri);
      return;
    }
    _policy.onPlaybackDebugSignal(payload, pageUri: pageUri);
  }

  Future<AdblockDecision> evaluate(AdblockRequestContext request) {
    final runtimeEngine = _runtimeEngine;
    if (runtimeEngine != null) {
      return runtimeEngine.evaluateAdblockRequest(request);
    }
    return _policy.evaluate(request);
  }
}
