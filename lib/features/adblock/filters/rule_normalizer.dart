import 'rule_models.dart';

class RuleNormalizer {
  const RuleNormalizer();

  ParsedFilterRules normalize(ParsedFilterRules parsed) {
    final normalizedNetwork = parsed.networkRules
        .map(_normalizeNetworkRule)
        .toList(growable: false);
    final normalizedCosmetic = parsed.cosmeticRules
        .map(_normalizeCosmeticRule)
        .toList(growable: false);
    final normalizedScriptlet = parsed.scriptInjectionRules
        .map(_normalizeScriptRule)
        .toList(growable: false);
    return ParsedFilterRules(
      networkRules: List<NetworkRule>.unmodifiable(normalizedNetwork),
      cosmeticRules: List<CosmeticRule>.unmodifiable(normalizedCosmetic),
      scriptInjectionRules: List<ScriptInjectionRule>.unmodifiable(
        normalizedScriptlet,
      ),
      parsedLineCount: parsed.parsedLineCount,
      ignoredLineCount: parsed.ignoredLineCount,
    );
  }

  NetworkRule _normalizeNetworkRule(NetworkRule rule) {
    final includeDomains = _normalizeSet(rule.includeDomains);
    final excludeDomains = _normalizeSet(rule.excludeDomains);
    final resourceTypes = _normalizeSet(rule.resourceTypes);
    final normalizedPattern = rule.isRegex
        ? rule.pattern.trim()
        : rule.pattern.trim().toLowerCase();
    var action = rule.action;
    var redirectTarget = _normalizeOptional(rule.redirectTarget);
    var rewriteTarget = _normalizeOptional(rule.rewriteTarget);

    if (rule.isException) {
      action = NetworkRuleAction.exception;
      redirectTarget = null;
      rewriteTarget = null;
    } else if (action == NetworkRuleAction.redirect && redirectTarget == null) {
      action = NetworkRuleAction.block;
    } else if (action == NetworkRuleAction.rewrite && rewriteTarget == null) {
      action = NetworkRuleAction.block;
    }

    return NetworkRule(
      id: rule.id,
      rawRule: rule.rawRule,
      pattern: normalizedPattern,
      action: action,
      isException: action == NetworkRuleAction.exception,
      isRegex: rule.isRegex,
      hostAnchored: rule.hostAnchored,
      includeDomains: includeDomains,
      excludeDomains: excludeDomains,
      resourceTypes: resourceTypes,
      thirdPartyOnly: rule.thirdPartyOnly,
      firstPartyOnly: rule.firstPartyOnly,
      redirectTarget: redirectTarget,
      rewriteTarget: rewriteTarget,
    );
  }

  CosmeticRule _normalizeCosmeticRule(CosmeticRule rule) {
    return CosmeticRule(
      id: rule.id,
      rawRule: rule.rawRule,
      selector: rule.selector.trim(),
      isException: rule.isException,
      includeDomains: _normalizeSet(rule.includeDomains),
      excludeDomains: _normalizeSet(rule.excludeDomains),
    );
  }

  ScriptInjectionRule _normalizeScriptRule(ScriptInjectionRule rule) {
    return ScriptInjectionRule(
      id: rule.id,
      rawRule: rule.rawRule,
      scriptletName: rule.scriptletName.trim(),
      arguments: List<String>.unmodifiable(
        rule.arguments
            .map((entry) => entry.trim())
            .where((entry) => entry.isNotEmpty),
      ),
      rawScript: rule.rawScript.trim(),
      includeDomains: _normalizeSet(rule.includeDomains),
      excludeDomains: _normalizeSet(rule.excludeDomains),
    );
  }

  Set<String> _normalizeSet(Set<String> values) {
    return Set<String>.unmodifiable(
      values
          .map((entry) => entry.trim().toLowerCase())
          .where((entry) => entry.isNotEmpty),
    );
  }

  String? _normalizeOptional(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }
}
