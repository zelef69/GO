import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../utils/tokenize.dart';
import 'rule_models.dart';

class IndexedFilterCompiler {
  const IndexedFilterCompiler();

  String computeRevision(Iterable<String> rawLines) {
    final normalized = rawLines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
    return sha256.convert(utf8.encode(normalized)).toString();
  }

  CompiledFilterSet compile({
    required ParsedFilterRules parsed,
    required Iterable<String> rawLines,
  }) {
    final networkTokenIndex = <String, List<int>>{};
    final networkDomainIndex = <String, List<int>>{};
    final networkResourceTypeIndex = <String, List<int>>{};
    final genericNetworkRuleIds = <int>{};
    final regexNetworkRuleIds = <int>{};
    final cosmeticDomainIndex = <String, List<int>>{};
    final genericCosmeticRuleIds = <int>{};
    final scriptletDomainIndex = <String, List<int>>{};
    final genericScriptletRuleIds = <int>{};

    for (final rule in parsed.networkRules) {
      final tokens = <String>{};
      if (!rule.isRegex) {
        tokens.addAll(tokenizePath(rule.pattern));
      }
      for (final domain in rule.includeDomains) {
        tokens.addAll(tokenizeHostname(domain));
      }
      var indexed = false;
      for (final token in tokens) {
        _appendIndex(networkTokenIndex, token, rule.id);
        indexed = true;
      }
      if (rule.includeDomains.isNotEmpty) {
        for (final domain in rule.includeDomains) {
          _appendIndex(networkDomainIndex, domain, rule.id);
          for (final token in tokenizeHostname(domain)) {
            _appendIndex(networkDomainIndex, token, rule.id);
          }
        }
        indexed = true;
      }
      if (rule.resourceTypes.isNotEmpty) {
        for (final resourceType in rule.resourceTypes) {
          _appendIndex(networkResourceTypeIndex, resourceType, rule.id);
        }
        indexed = true;
      }
      if (!indexed) {
        if (rule.isRegex) {
          regexNetworkRuleIds.add(rule.id);
        } else {
          genericNetworkRuleIds.add(rule.id);
        }
      } else if (rule.isRegex) {
        regexNetworkRuleIds.add(rule.id);
      }
    }

    for (final rule in parsed.cosmeticRules) {
      if (rule.includeDomains.isEmpty) {
        genericCosmeticRuleIds.add(rule.id);
      } else {
        for (final domain in rule.includeDomains) {
          _appendIndex(cosmeticDomainIndex, domain, rule.id);
          for (final token in tokenizeHostname(domain)) {
            _appendIndex(cosmeticDomainIndex, token, rule.id);
          }
        }
      }
    }

    for (final rule in parsed.scriptInjectionRules) {
      if (rule.includeDomains.isEmpty) {
        genericScriptletRuleIds.add(rule.id);
      } else {
        for (final domain in rule.includeDomains) {
          _appendIndex(scriptletDomainIndex, domain, rule.id);
          for (final token in tokenizeHostname(domain)) {
            _appendIndex(scriptletDomainIndex, token, rule.id);
          }
        }
      }
    }

    return CompiledFilterSet(
      revision: computeRevision(rawLines),
      networkRules: parsed.networkRules,
      cosmeticRules: parsed.cosmeticRules,
      scriptInjectionRules: parsed.scriptInjectionRules,
      networkTokenIndex: _freeze(networkTokenIndex),
      networkDomainIndex: _freeze(networkDomainIndex),
      networkResourceTypeIndex: _freeze(networkResourceTypeIndex),
      genericNetworkRuleIds: Set<int>.unmodifiable(genericNetworkRuleIds),
      regexNetworkRuleIds: Set<int>.unmodifiable(regexNetworkRuleIds),
      cosmeticDomainIndex: _freeze(cosmeticDomainIndex),
      genericCosmeticRuleIds: Set<int>.unmodifiable(genericCosmeticRuleIds),
      scriptletDomainIndex: _freeze(scriptletDomainIndex),
      genericScriptletRuleIds: Set<int>.unmodifiable(genericScriptletRuleIds),
    );
  }

  void _appendIndex(Map<String, List<int>> index, String rawKey, int value) {
    final key = rawKey.trim().toLowerCase();
    if (key.isEmpty) {
      return;
    }
    final existing = index[key];
    if (existing == null) {
      index[key] = <int>[value];
      return;
    }
    if (existing.isEmpty || existing.last != value) {
      existing.add(value);
    }
  }

  Map<String, List<int>> _freeze(Map<String, List<int>> source) {
    final copy = <String, List<int>>{};
    for (final entry in source.entries) {
      copy[entry.key] = List<int>.unmodifiable(entry.value);
    }
    return Map<String, List<int>>.unmodifiable(copy);
  }
}
