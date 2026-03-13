import '../core/types.dart';
import '../filters/rule_models.dart';
import '../utils/tokenize.dart';

class CosmeticMatcher {
  const CosmeticMatcher();

  CosmeticRules match(PageContext context, CompiledFilterSet compiled) {
    if (compiled.cosmeticRules.isEmpty) {
      return CosmeticRules.empty();
    }
    final byId = compiled.cosmeticRuleById();
    final candidates = <int>{};
    candidates.addAll(compiled.genericCosmeticRuleIds);
    for (final token in tokenizeHostname(context.hostname)) {
      candidates.addAll(compiled.cosmeticDomainIndex[token] ?? const <int>[]);
    }
    if (candidates.isEmpty) {
      return CosmeticRules.empty();
    }

    final blockedSelectors = <String>{};
    final exceptSelectors = <String>{};
    final host = context.hostname.toLowerCase();
    final domain = context.domain.toLowerCase();

    for (final id in candidates) {
      final rule = byId[id];
      if (rule == null) {
        continue;
      }
      if (!_matchesDomainScope(rule, host, domain)) {
        continue;
      }
      if (rule.isException) {
        exceptSelectors.add(rule.selector);
      } else {
        blockedSelectors.add(rule.selector);
      }
    }

    blockedSelectors.removeAll(exceptSelectors);
    if (blockedSelectors.isEmpty && exceptSelectors.isEmpty) {
      return CosmeticRules.empty();
    }
    return CosmeticRules(
      selectors: blockedSelectors,
      exceptions: exceptSelectors,
      generichide: false,
    );
  }

  bool _matchesDomainScope(CosmeticRule rule, String host, String domain) {
    if (rule.includeDomains.isNotEmpty) {
      var matchedInclude = false;
      for (final includeDomain in rule.includeDomains) {
        final normalized = includeDomain.toLowerCase();
        if (host == normalized ||
            host.endsWith('.$normalized') ||
            domain == normalized) {
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
      if (host == normalized ||
          host.endsWith('.$normalized') ||
          domain == normalized) {
        return false;
      }
    }
    return true;
  }
}
