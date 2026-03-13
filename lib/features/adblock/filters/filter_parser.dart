import 'rule_models.dart';

class FilterParser {
  const FilterParser();

  ParsedFilterRules parse(Iterable<String> rawLines) {
    final networkRules = <NetworkRule>[];
    final cosmeticRules = <CosmeticRule>[];
    final scriptInjectionRules = <ScriptInjectionRule>[];
    var parsedLineCount = 0;
    var ignoredLineCount = 0;
    var nextRuleId = 0;

    for (final rawLine in rawLines) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('!') || line.startsWith('[')) {
        continue;
      }
      parsedLineCount += 1;

      final scriptRule = _parseScriptInjectionRule(
        line,
        nextRuleId: nextRuleId,
      );
      if (scriptRule != null) {
        scriptInjectionRules.add(scriptRule);
        nextRuleId += 1;
        continue;
      }

      final cosmeticRule = _parseCosmeticRule(line, nextRuleId: nextRuleId);
      if (cosmeticRule != null) {
        cosmeticRules.add(cosmeticRule);
        nextRuleId += 1;
        continue;
      }

      final networkRule = _parseNetworkRule(line, nextRuleId: nextRuleId);
      if (networkRule != null) {
        networkRules.add(networkRule);
        nextRuleId += 1;
        continue;
      }

      ignoredLineCount += 1;
    }

    return ParsedFilterRules(
      networkRules: List<NetworkRule>.unmodifiable(networkRules),
      cosmeticRules: List<CosmeticRule>.unmodifiable(cosmeticRules),
      scriptInjectionRules: List<ScriptInjectionRule>.unmodifiable(
        scriptInjectionRules,
      ),
      parsedLineCount: parsedLineCount,
      ignoredLineCount: ignoredLineCount,
    );
  }

  NetworkRule? _parseNetworkRule(String line, {required int nextRuleId}) {
    var working = line;
    var isException = false;
    if (working.startsWith('@@')) {
      isException = true;
      working = working.substring(2).trim();
    }
    if (working.isEmpty) {
      return null;
    }

    final splitIndex = working.indexOf(r'$');
    final addressPart =
        (splitIndex == -1 ? working : working.substring(0, splitIndex)).trim();
    final optionsPart = splitIndex == -1
        ? ''
        : working.substring(splitIndex + 1).trim();
    if (addressPart.isEmpty) {
      return null;
    }

    final optionState = _parseOptions(optionsPart);
    final parsedPattern = _parseNetworkPattern(addressPart);
    if (parsedPattern == null) {
      return null;
    }

    return NetworkRule(
      id: nextRuleId,
      rawRule: line,
      pattern: parsedPattern.pattern,
      action: isException
          ? NetworkRuleAction.exception
          : optionState.redirectTarget != null
          ? NetworkRuleAction.redirect
          : optionState.rewriteTarget != null
          ? NetworkRuleAction.rewrite
          : NetworkRuleAction.block,
      isException: isException,
      isRegex: parsedPattern.isRegex,
      hostAnchored: parsedPattern.hostAnchored,
      includeDomains: optionState.includeDomains,
      excludeDomains: optionState.excludeDomains,
      resourceTypes: optionState.resourceTypes,
      thirdPartyOnly: optionState.thirdPartyOnly,
      firstPartyOnly: optionState.firstPartyOnly,
      redirectTarget: optionState.redirectTarget,
      rewriteTarget: optionState.rewriteTarget,
    );
  }

  CosmeticRule? _parseCosmeticRule(String line, {required int nextRuleId}) {
    final exceptionSeparator = line.indexOf('#@#');
    final hideSeparator = line.indexOf('##');
    if (exceptionSeparator == -1 && hideSeparator == -1) {
      return null;
    }
    final useException = exceptionSeparator != -1;
    final separatorIndex = useException ? exceptionSeparator : hideSeparator;
    final separatorLength = useException ? 3 : 2;
    final domainPart = line.substring(0, separatorIndex).trim();
    final selector = line.substring(separatorIndex + separatorLength).trim();
    if (selector.isEmpty) {
      return null;
    }
    final scope = _parseDomainScope(domainPart);
    return CosmeticRule(
      id: nextRuleId,
      rawRule: line,
      selector: selector,
      isException: useException,
      includeDomains: scope.includeDomains,
      excludeDomains: scope.excludeDomains,
    );
  }

  ScriptInjectionRule? _parseScriptInjectionRule(
    String line, {
    required int nextRuleId,
  }) {
    final scriptSeparator = line.indexOf(r'#$#');
    if (scriptSeparator != -1) {
      final domainPart = line.substring(0, scriptSeparator).trim();
      final rawScript = line.substring(scriptSeparator + 3).trim();
      if (rawScript.isEmpty) {
        return null;
      }
      final scope = _parseDomainScope(domainPart);
      return ScriptInjectionRule(
        id: nextRuleId,
        rawRule: line,
        scriptletName: '',
        arguments: const <String>[],
        rawScript: rawScript,
        includeDomains: scope.includeDomains,
        excludeDomains: scope.excludeDomains,
      );
    }

    final plusJsSeparator = line.indexOf('##+js(');
    if (plusJsSeparator == -1 || !line.endsWith(')')) {
      return null;
    }
    final domainPart = line.substring(0, plusJsSeparator).trim();
    final payload = line
        .substring(plusJsSeparator + '##+js('.length, line.length - 1)
        .trim();
    if (payload.isEmpty) {
      return null;
    }
    final scriptlet = _parseScriptletPayload(payload);
    final scope = _parseDomainScope(domainPart);
    return ScriptInjectionRule(
      id: nextRuleId,
      rawRule: line,
      scriptletName: scriptlet.name,
      arguments: scriptlet.arguments,
      rawScript: '',
      includeDomains: scope.includeDomains,
      excludeDomains: scope.excludeDomains,
    );
  }

  _ParsedNetworkPattern? _parseNetworkPattern(String rawPattern) {
    var pattern = rawPattern.trim();
    var hostAnchored = false;
    var isRegex = false;

    if (pattern.startsWith('||')) {
      hostAnchored = true;
      pattern = pattern.substring(2);
    }
    if (pattern.endsWith('|')) {
      pattern = pattern.substring(0, pattern.length - 1);
    }
    final anchorIndex = pattern.indexOf('^');
    if (anchorIndex != -1) {
      pattern = pattern.substring(0, anchorIndex);
    }
    pattern = pattern.trim();
    if (pattern.isEmpty) {
      return null;
    }

    if (pattern.startsWith('/') &&
        pattern.endsWith('/') &&
        pattern.length > 2) {
      isRegex = true;
      pattern = pattern.substring(1, pattern.length - 1);
    } else {
      pattern = pattern
          .replaceAll('|', '')
          .replaceAll('*', '')
          .replaceAll('^', '')
          .toLowerCase();
    }

    if (pattern.isEmpty) {
      return null;
    }
    return _ParsedNetworkPattern(
      pattern: pattern,
      hostAnchored: hostAnchored,
      isRegex: isRegex,
    );
  }

  _OptionState _parseOptions(String optionsPart) {
    final includeDomains = <String>{};
    final excludeDomains = <String>{};
    final resourceTypes = <String>{};
    var thirdPartyOnly = false;
    var firstPartyOnly = false;
    String? redirectTarget;
    String? rewriteTarget;

    if (optionsPart.isNotEmpty) {
      final tokens = optionsPart.split(',');
      for (final rawToken in tokens) {
        final token = rawToken.trim();
        if (token.isEmpty) {
          continue;
        }
        final tokenLower = token.toLowerCase();
        if (tokenLower.startsWith('domain=')) {
          final spec = token.substring(token.indexOf('=') + 1);
          final scope = _parseDomainScope(spec);
          includeDomains.addAll(scope.includeDomains);
          excludeDomains.addAll(scope.excludeDomains);
          continue;
        }
        if (tokenLower == 'third-party') {
          thirdPartyOnly = true;
          firstPartyOnly = false;
          continue;
        }
        if (tokenLower == '~third-party') {
          firstPartyOnly = true;
          thirdPartyOnly = false;
          continue;
        }
        if (tokenLower.startsWith('redirect=')) {
          final value = token.substring(token.indexOf('=') + 1).trim();
          if (value.isNotEmpty) {
            redirectTarget = value;
          }
          continue;
        }
        if (tokenLower.startsWith('rewrite=')) {
          final value = token.substring(token.indexOf('=') + 1).trim();
          if (value.isNotEmpty) {
            rewriteTarget = value;
          }
          continue;
        }
        if (_knownResourceTypes.contains(tokenLower)) {
          resourceTypes.add(tokenLower);
        }
      }
    }

    return _OptionState(
      includeDomains: includeDomains,
      excludeDomains: excludeDomains,
      resourceTypes: resourceTypes,
      thirdPartyOnly: thirdPartyOnly,
      firstPartyOnly: firstPartyOnly,
      redirectTarget: redirectTarget,
      rewriteTarget: rewriteTarget,
    );
  }

  _DomainScope _parseDomainScope(String rawDomainSpec) {
    final includeDomains = <String>{};
    final excludeDomains = <String>{};
    final tokens = rawDomainSpec.split(RegExp(r'[,\|]'));
    for (final rawToken in tokens) {
      final token = rawToken.trim().toLowerCase();
      if (token.isEmpty) {
        continue;
      }
      if (token.startsWith('~')) {
        final domain = token.substring(1).trim();
        if (domain.isNotEmpty) {
          excludeDomains.add(domain);
        }
      } else {
        includeDomains.add(token);
      }
    }
    return _DomainScope(
      includeDomains: includeDomains,
      excludeDomains: excludeDomains,
    );
  }

  _ParsedScriptlet _parseScriptletPayload(String payload) {
    final parts = payload
        .split(',')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      return const _ParsedScriptlet(name: '', arguments: <String>[]);
    }
    return _ParsedScriptlet(
      name: parts.first,
      arguments: parts.skip(1).toList(growable: false),
    );
  }

  static const Set<String> _knownResourceTypes = <String>{
    'script',
    'stylesheet',
    'image',
    'font',
    'media',
    'xmlhttprequest',
    'subdocument',
    'document',
    'other',
  };
}

class _ParsedNetworkPattern {
  const _ParsedNetworkPattern({
    required this.pattern,
    required this.hostAnchored,
    required this.isRegex,
  });

  final String pattern;
  final bool hostAnchored;
  final bool isRegex;
}

class _OptionState {
  const _OptionState({
    required this.includeDomains,
    required this.excludeDomains,
    required this.resourceTypes,
    required this.thirdPartyOnly,
    required this.firstPartyOnly,
    required this.redirectTarget,
    required this.rewriteTarget,
  });

  final Set<String> includeDomains;
  final Set<String> excludeDomains;
  final Set<String> resourceTypes;
  final bool thirdPartyOnly;
  final bool firstPartyOnly;
  final String? redirectTarget;
  final String? rewriteTarget;
}

class _DomainScope {
  const _DomainScope({
    required this.includeDomains,
    required this.excludeDomains,
  });

  final Set<String> includeDomains;
  final Set<String> excludeDomains;
}

class _ParsedScriptlet {
  const _ParsedScriptlet({required this.name, required this.arguments});

  final String name;
  final List<String> arguments;
}
