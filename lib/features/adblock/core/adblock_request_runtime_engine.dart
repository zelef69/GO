import 'adblock_config.dart';
import 'request_runtime_models.dart';
import 'types.dart';

abstract interface class AdblockRequestRuntimeEngine
    implements AdblockRuntimeEngine {
  Future<AdblockDecision> evaluateAdblockRequest(AdblockRequestContext request);

  void setRuntimeConfig(AdblockConfig config);

  void setFirstPartyHeuristicProfile(bool enabled);

  void clearRuntimeCache();

  void onPlaybackDebugSignal(Map<String, dynamic> payload, {Uri? pageUri});
}
