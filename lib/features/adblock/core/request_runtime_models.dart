import '../intercept/request_interceptor.dart';
import 'types.dart';

class AdblockRequestContext {
  const AdblockRequestContext({
    required this.uri,
    required this.resourceType,
    required this.sourceUrl,
    required this.fromServiceWorker,
    required this.adShowing,
    this.playbackStalled = false,
    this.adSignalKey,
  });

  final Uri uri;
  final String resourceType;
  final Uri? sourceUrl;
  final bool fromServiceWorker;
  final bool adShowing;
  final bool playbackStalled;
  final String? adSignalKey;

  RequestContext toRequestContext(RequestInterceptor interceptor) {
    return interceptor.normalize(
      url: uri,
      resourceType: resourceType,
      frameUrl: sourceUrl,
      topLevelUrl: sourceUrl,
    );
  }
}

class AdblockDecision {
  const AdblockDecision({
    required this.blocked,
    required this.reason,
    this.action = DecisionAction.allow,
    this.matchedRule,
    this.exceptionRule,
    this.redirectDataUrl,
    this.rewrittenUrl,
    this.fromCache = false,
    this.candidateCount = 0,
    this.evaluatedCount = 0,
  });

  final bool blocked;
  final String reason;
  final DecisionAction action;
  final String? matchedRule;
  final String? exceptionRule;
  final String? redirectDataUrl;
  final String? rewrittenUrl;
  final bool fromCache;
  final int candidateCount;
  final int evaluatedCount;

  DecisionAction get effectiveAction {
    if (action != DecisionAction.allow) {
      return action;
    }
    if ((redirectDataUrl ?? '').trim().isNotEmpty) {
      return DecisionAction.redirect;
    }
    if ((rewrittenUrl ?? '').trim().isNotEmpty) {
      return DecisionAction.rewriteResponse;
    }
    if (blocked) {
      return DecisionAction.block;
    }
    return DecisionAction.allow;
  }
}
