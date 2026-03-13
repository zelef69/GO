import 'dart:collection';

enum NetworkRuleAction { block, exception, redirect, rewrite }

class NetworkRule {
  const NetworkRule({
    required this.id,
    required this.rawRule,
    required this.pattern,
    required this.action,
    required this.isException,
    required this.isRegex,
    required this.hostAnchored,
    required this.includeDomains,
    required this.excludeDomains,
    required this.resourceTypes,
    required this.thirdPartyOnly,
    required this.firstPartyOnly,
    this.redirectTarget,
    this.rewriteTarget,
  });

  final int id;
  final String rawRule;
  final String pattern;
  final NetworkRuleAction action;
  final bool isException;
  final bool isRegex;
  final bool hostAnchored;
  final Set<String> includeDomains;
  final Set<String> excludeDomains;
  final Set<String> resourceTypes;
  final bool thirdPartyOnly;
  final bool firstPartyOnly;
  final String? redirectTarget;
  final String? rewriteTarget;

  bool get isRedirect => action == NetworkRuleAction.redirect;
  bool get isRewrite => action == NetworkRuleAction.rewrite;
}

class CosmeticRule {
  const CosmeticRule({
    required this.id,
    required this.rawRule,
    required this.selector,
    required this.isException,
    required this.includeDomains,
    required this.excludeDomains,
  });

  final int id;
  final String rawRule;
  final String selector;
  final bool isException;
  final Set<String> includeDomains;
  final Set<String> excludeDomains;
}

class ScriptInjectionRule {
  const ScriptInjectionRule({
    required this.id,
    required this.rawRule,
    required this.scriptletName,
    required this.arguments,
    required this.rawScript,
    required this.includeDomains,
    required this.excludeDomains,
  });

  final int id;
  final String rawRule;
  final String scriptletName;
  final List<String> arguments;
  final String rawScript;
  final Set<String> includeDomains;
  final Set<String> excludeDomains;
}

class ParsedFilterRules {
  const ParsedFilterRules({
    required this.networkRules,
    required this.cosmeticRules,
    required this.scriptInjectionRules,
    required this.parsedLineCount,
    required this.ignoredLineCount,
  });

  final List<NetworkRule> networkRules;
  final List<CosmeticRule> cosmeticRules;
  final List<ScriptInjectionRule> scriptInjectionRules;
  final int parsedLineCount;
  final int ignoredLineCount;
}

class CompiledFilterSet {
  const CompiledFilterSet({
    required this.revision,
    required this.networkRules,
    required this.cosmeticRules,
    required this.scriptInjectionRules,
    required this.networkTokenIndex,
    required this.networkDomainIndex,
    required this.networkResourceTypeIndex,
    required this.genericNetworkRuleIds,
    required this.regexNetworkRuleIds,
    required this.cosmeticDomainIndex,
    required this.genericCosmeticRuleIds,
    required this.scriptletDomainIndex,
    required this.genericScriptletRuleIds,
  });

  factory CompiledFilterSet.empty() {
    return const CompiledFilterSet(
      revision: '',
      networkRules: <NetworkRule>[],
      cosmeticRules: <CosmeticRule>[],
      scriptInjectionRules: <ScriptInjectionRule>[],
      networkTokenIndex: <String, List<int>>{},
      networkDomainIndex: <String, List<int>>{},
      networkResourceTypeIndex: <String, List<int>>{},
      genericNetworkRuleIds: <int>{},
      regexNetworkRuleIds: <int>{},
      cosmeticDomainIndex: <String, List<int>>{},
      genericCosmeticRuleIds: <int>{},
      scriptletDomainIndex: <String, List<int>>{},
      genericScriptletRuleIds: <int>{},
    );
  }

  final String revision;
  final List<NetworkRule> networkRules;
  final List<CosmeticRule> cosmeticRules;
  final List<ScriptInjectionRule> scriptInjectionRules;
  final Map<String, List<int>> networkTokenIndex;
  final Map<String, List<int>> networkDomainIndex;
  final Map<String, List<int>> networkResourceTypeIndex;
  final Set<int> genericNetworkRuleIds;
  final Set<int> regexNetworkRuleIds;
  final Map<String, List<int>> cosmeticDomainIndex;
  final Set<int> genericCosmeticRuleIds;
  final Map<String, List<int>> scriptletDomainIndex;
  final Set<int> genericScriptletRuleIds;

  Map<int, NetworkRule> networkRuleById() {
    final map = LinkedHashMap<int, NetworkRule>();
    for (final rule in networkRules) {
      map[rule.id] = rule;
    }
    return map;
  }

  Map<int, CosmeticRule> cosmeticRuleById() {
    final map = LinkedHashMap<int, CosmeticRule>();
    for (final rule in cosmeticRules) {
      map[rule.id] = rule;
    }
    return map;
  }

  Map<int, ScriptInjectionRule> scriptletRuleById() {
    final map = LinkedHashMap<int, ScriptInjectionRule>();
    for (final rule in scriptInjectionRules) {
      map[rule.id] = rule;
    }
    return map;
  }
}
