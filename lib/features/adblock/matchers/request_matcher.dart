import '../core/types.dart';
import '../filters/rule_models.dart';
import '../utils/tokenize.dart';
import 'redirect_target_resolver.dart';

class RequestCandidates {
  const RequestCandidates({
    required this.nonRegexRuleIds,
    required this.regexRuleIds,
  });

  final Set<int> nonRegexRuleIds;
  final Set<int> regexRuleIds;

  int get candidateCount => nonRegexRuleIds.length + regexRuleIds.length;
}

class RequestMatcher {
  const RequestMatcher({
    RedirectTargetResolver redirectTargetResolver =
        const RedirectTargetResolver(),
    RewriteTargetResolver rewriteTargetResolver = const RewriteTargetResolver(),
  }) : _redirectTargetResolver = redirectTargetResolver,
       _rewriteTargetResolver = rewriteTargetResolver;

  final RedirectTargetResolver _redirectTargetResolver;
  final RewriteTargetResolver _rewriteTargetResolver;

  RequestCandidates findCandidates(
    RequestContext context,
    CompiledFilterSet compiled,
  ) {
    final allById = compiled.networkRuleById();
    if (allById.isEmpty) {
      return const RequestCandidates(
        nonRegexRuleIds: <int>{},
        regexRuleIds: <int>{},
      );
    }
    final hostTokens = tokenizeHostname(context.hostname);
    final urlTokens = tokenizeUrl(context.url);
    final nonRegexCandidateIds = <int>{};
    final regexCandidateIds = <int>{};

    for (final token in hostTokens) {
      for (final ruleId
          in compiled.networkDomainIndex[token] ?? const <int>[]) {
        final rule = allById[ruleId];
        if (rule == null) {
          continue;
        }
        if (rule.isRegex) {
          regexCandidateIds.add(ruleId);
        } else {
          nonRegexCandidateIds.add(ruleId);
        }
      }
    }
    for (final token in urlTokens) {
      for (final ruleId in compiled.networkTokenIndex[token] ?? const <int>[]) {
        final rule = allById[ruleId];
        if (rule == null) {
          continue;
        }
        if (rule.isRegex) {
          regexCandidateIds.add(ruleId);
        } else {
          nonRegexCandidateIds.add(ruleId);
        }
      }
    }

    for (final ruleId
        in compiled.networkResourceTypeIndex[context.resourceType] ??
            const <int>[]) {
      final rule = allById[ruleId];
      if (rule == null) {
        continue;
      }
      if (rule.isRegex) {
        regexCandidateIds.add(ruleId);
      } else {
        nonRegexCandidateIds.add(ruleId);
      }
    }
    nonRegexCandidateIds.addAll(compiled.genericNetworkRuleIds);
    if (regexCandidateIds.isEmpty) {
      regexCandidateIds.addAll(compiled.regexNetworkRuleIds);
    }

    if (nonRegexCandidateIds.isEmpty && regexCandidateIds.isEmpty) {
      for (final entry in allById.entries) {
        if (entry.value.isRegex) {
          regexCandidateIds.add(entry.key);
        } else {
          nonRegexCandidateIds.add(entry.key);
        }
      }
    }

    return RequestCandidates(
      nonRegexRuleIds: Set<int>.unmodifiable(nonRegexCandidateIds),
      regexRuleIds: Set<int>.unmodifiable(regexCandidateIds),
    );
  }

  NetworkMatchDecision evaluateCandidates(
    RequestContext context,
    CompiledFilterSet compiled,
    RequestCandidates candidates,
  ) {
    if (compiled.networkRules.isEmpty) {
      return NetworkMatchDecision.allow(reason: 'no_network_rules');
    }
    final allById = compiled.networkRuleById();
    final requestUrlLower = context.url.toString().toLowerCase();
    final pathLower = context.path.toLowerCase();
    final hostLower = context.hostname.toLowerCase();
    var evaluatedCount = 0;
    var usedRegexFallback = false;
    final nonRegexRules = _sortedRules(
      candidates.nonRegexRuleIds,
      allById,
      regexOnly: false,
    );
    final regexRules = _sortedRules(
      candidates.regexRuleIds,
      allById,
      regexOnly: true,
    );

    NetworkRule? matchedNonRegexAction;
    for (final rule in nonRegexRules) {
      if (!_ruleApplies(rule, context)) {
        continue;
      }
      evaluatedCount += 1;
      if (!_matchesPattern(rule, requestUrlLower, hostLower, pathLower)) {
        continue;
      }
      if (rule.action == NetworkRuleAction.exception) {
        return NetworkMatchDecision.allow(
          reason: 'exception_rule',
          exceptionRule: rule.rawRule,
          candidateCount: candidates.candidateCount,
          evaluatedCount: evaluatedCount,
        );
      }
      matchedNonRegexAction ??= rule;
    }

    if (matchedNonRegexAction != null) {
      // Regex exceptions are evaluated only when a non-regex blocking action
      // already matched, keeping regex evaluation out of the fast path.
      for (final rule in regexRules) {
        if (rule.action != NetworkRuleAction.exception) {
          continue;
        }
        if (!_ruleApplies(rule, context)) {
          continue;
        }
        usedRegexFallback = true;
        evaluatedCount += 1;
        if (_matchesPattern(rule, requestUrlLower, hostLower, pathLower)) {
          return NetworkMatchDecision.allow(
            reason: 'exception_rule_regex',
            exceptionRule: rule.rawRule,
            candidateCount: candidates.candidateCount,
            evaluatedCount: evaluatedCount,
            usedRegexFallback: usedRegexFallback,
          );
        }
      }
      return _decisionFromMatchedRule(
        context: context,
        rule: matchedNonRegexAction,
        candidateCount: candidates.candidateCount,
        evaluatedCount: evaluatedCount,
        usedRegexFallback: usedRegexFallback,
        regexPath: false,
      );
    }

    NetworkRule? matchedRegexAction;
    if (regexRules.isNotEmpty) {
      usedRegexFallback = true;
    }
    for (final rule in regexRules) {
      if (!_ruleApplies(rule, context)) {
        continue;
      }
      evaluatedCount += 1;
      if (!_matchesPattern(rule, requestUrlLower, hostLower, pathLower)) {
        continue;
      }
      if (rule.action == NetworkRuleAction.exception) {
        return NetworkMatchDecision.allow(
          reason: 'exception_rule_regex',
          exceptionRule: rule.rawRule,
          candidateCount: candidates.candidateCount,
          evaluatedCount: evaluatedCount,
          usedRegexFallback: usedRegexFallback,
        );
      }
      matchedRegexAction ??= rule;
    }

    if (matchedRegexAction != null) {
      return _decisionFromMatchedRule(
        context: context,
        rule: matchedRegexAction,
        candidateCount: candidates.candidateCount,
        evaluatedCount: evaluatedCount,
        usedRegexFallback: usedRegexFallback,
        regexPath: true,
      );
    }
    return NetworkMatchDecision.allow(
      reason: 'compiled_allow',
      candidateCount: candidates.candidateCount,
      evaluatedCount: evaluatedCount,
      usedRegexFallback: usedRegexFallback,
    );
  }

  NetworkMatchDecision match(
    RequestContext context,
    CompiledFilterSet compiled,
  ) {
    final candidates = findCandidates(context, compiled);
    return evaluateCandidates(context, compiled, candidates);
  }

  bool _ruleApplies(NetworkRule rule, RequestContext context) {
    if (!_matchesResourceType(rule, context.resourceType)) {
      return false;
    }
    if (!_matchesPartyScope(rule, context.isThirdParty)) {
      return false;
    }
    if (!_matchesDomainScope(rule, context)) {
      return false;
    }
    return true;
  }

  bool _matchesDomainScope(NetworkRule rule, RequestContext context) {
    final sourceHost = context.frameHostname.isNotEmpty
        ? context.frameHostname.toLowerCase()
        : context.topLevelHostname.isNotEmpty
        ? context.topLevelHostname.toLowerCase()
        : (context.frameUrl ?? context.topLevelUrl)?.host.toLowerCase() ?? '';
    final sourceDomain = sourceHost.isEmpty
        ? ''
        : registrableDomainFromHost(sourceHost);
    if (rule.includeDomains.isNotEmpty) {
      var matchedInclude = false;
      for (final includeDomain in rule.includeDomains) {
        final normalized = includeDomain.toLowerCase();
        if (normalized.isEmpty) {
          continue;
        }
        if (sourceHost == normalized ||
            sourceHost.endsWith('.$normalized') ||
            sourceDomain == normalized) {
          matchedInclude = true;
          break;
        }
      }
      if (!matchedInclude) {
        return false;
      }
    }

    for (final excludeDomain in rule.excludeDomains) {
      final normalized = excludeDomain.toLowerCase();
      if (normalized.isEmpty) {
        continue;
      }
      if (sourceHost == normalized ||
          sourceHost.endsWith('.$normalized') ||
          sourceDomain == normalized) {
        return false;
      }
    }

    return true;
  }

  bool _matchesResourceType(NetworkRule rule, String resourceType) {
    if (rule.resourceTypes.isEmpty) {
      return true;
    }
    return rule.resourceTypes.contains(resourceType);
  }

  bool _matchesPartyScope(NetworkRule rule, bool isThirdParty) {
    if (rule.thirdPartyOnly && !isThirdParty) {
      return false;
    }
    if (rule.firstPartyOnly && isThirdParty) {
      return false;
    }
    return true;
  }

  bool _matchesPattern(
    NetworkRule rule,
    String requestUrlLower,
    String hostLower,
    String pathLower,
  ) {
    if (rule.isRegex) {
      try {
        return RegExp(
          rule.pattern,
          caseSensitive: false,
        ).hasMatch(requestUrlLower);
      } catch (_) {
        return false;
      }
    }
    final pattern = rule.pattern.toLowerCase();
    if (rule.hostAnchored) {
      final slashIndex = pattern.indexOf('/');
      if (slashIndex == -1) {
        return hostLower == pattern || hostLower.endsWith('.$pattern');
      }
      final hostPart = pattern.substring(0, slashIndex);
      final pathPart = pattern.substring(slashIndex);
      final hostMatched =
          hostLower == hostPart || hostLower.endsWith('.$hostPart');
      if (!hostMatched) {
        return false;
      }
      if (pathPart.isEmpty) {
        return true;
      }
      return pathLower.contains(pathPart);
    }
    return requestUrlLower.contains(pattern);
  }

  List<NetworkRule> _sortedRules(
    Set<int> ids,
    Map<int, NetworkRule> allById, {
    required bool regexOnly,
  }) {
    final rules = <NetworkRule>[];
    for (final id in ids) {
      final rule = allById[id];
      if (rule == null || rule.isRegex != regexOnly) {
        continue;
      }
      rules.add(rule);
    }
    rules.sort((left, right) => left.id.compareTo(right.id));
    return rules;
  }

  NetworkMatchDecision _decisionFromMatchedRule({
    required RequestContext context,
    required NetworkRule rule,
    required int candidateCount,
    required int evaluatedCount,
    required bool usedRegexFallback,
    required bool regexPath,
  }) {
    final suffix = regexPath ? '_regex' : '';
    switch (rule.action) {
      case NetworkRuleAction.block:
        return NetworkMatchDecision(
          blocked: true,
          action: DecisionAction.block,
          reason: 'compiled_network_rule$suffix',
          matchedRule: rule.rawRule,
          candidateCount: candidateCount,
          evaluatedCount: evaluatedCount,
          usedRegexFallback: usedRegexFallback,
        );
      case NetworkRuleAction.redirect:
        final target = _redirectTargetResolver.resolve(
          rule.redirectTarget,
          context: context,
        );
        if ((target ?? '').isEmpty) {
          return NetworkMatchDecision(
            blocked: true,
            action: DecisionAction.block,
            reason: 'compiled_network_rule$suffix',
            matchedRule: rule.rawRule,
            candidateCount: candidateCount,
            evaluatedCount: evaluatedCount,
            usedRegexFallback: usedRegexFallback,
          );
        }
        return NetworkMatchDecision(
          blocked: true,
          action: DecisionAction.redirect,
          reason: 'compiled_network_redirect_rule$suffix',
          matchedRule: rule.rawRule,
          redirectDataUrl: target,
          candidateCount: candidateCount,
          evaluatedCount: evaluatedCount,
          usedRegexFallback: usedRegexFallback,
        );
      case NetworkRuleAction.rewrite:
        final target = _rewriteTargetResolver.resolve(
          rule.rewriteTarget,
          context: context,
        );
        if ((target ?? '').isEmpty) {
          return NetworkMatchDecision(
            blocked: true,
            action: DecisionAction.block,
            reason: 'compiled_network_rule$suffix',
            matchedRule: rule.rawRule,
            candidateCount: candidateCount,
            evaluatedCount: evaluatedCount,
            usedRegexFallback: usedRegexFallback,
          );
        }
        return NetworkMatchDecision(
          blocked: false,
          action: DecisionAction.rewriteResponse,
          reason: 'compiled_network_rewrite_rule$suffix',
          matchedRule: rule.rawRule,
          rewrittenUrl: target,
          candidateCount: candidateCount,
          evaluatedCount: evaluatedCount,
          usedRegexFallback: usedRegexFallback,
        );
      case NetworkRuleAction.exception:
        return NetworkMatchDecision.allow(
          reason: regexPath ? 'exception_rule_regex' : 'exception_rule',
          exceptionRule: rule.rawRule,
          candidateCount: candidateCount,
          evaluatedCount: evaluatedCount,
          usedRegexFallback: usedRegexFallback,
        );
    }
  }
}
