import '../../../shared/utils/host_matcher.dart';

enum AdblockRuleType { domainSuffix, substring }

class AdblockRule {
  const AdblockRule({
    required this.rawRule,
    required this.type,
    required this.pattern,
  });

  final String rawRule;
  final AdblockRuleType type;
  final String pattern;

  static AdblockRule? parse(String input) {
    final line = input.trim();
    if (line.isEmpty || line.startsWith('!') || line.startsWith('#')) {
      return null;
    }

    if (line.startsWith('@@')) {
      return null;
    }

    if (line.startsWith('||')) {
      final bodyWithOptions = line.substring(2).trim();
      final optionsSeparator = bodyWithOptions.indexOf('\$');
      final hasOptions = optionsSeparator != -1;
      final addressPart =
          (optionsSeparator == -1
                  ? bodyWithOptions
                  : bodyWithOptions.substring(0, optionsSeparator))
              .trim()
              .toLowerCase();
      final anchorSeparator = addressPart.indexOf('^');
      final target =
          (anchorSeparator == -1
                  ? addressPart
                  : addressPart.substring(0, anchorSeparator))
              .trim();
      if (target.isEmpty) {
        return null;
      }

      if (target.contains('/')) {
        // This lightweight matcher cannot safely interpret rule options
        // for URL/path rules. Parsing these as plain substrings can
        // over-block playback requests (e.g. videoplayback).
        if (hasOptions) {
          return null;
        }
        final pathPattern = target.replaceAll('*', '').replaceAll('^', '');
        if (pathPattern.isEmpty) {
          return null;
        }
        return AdblockRule(
          rawRule: line,
          type: AdblockRuleType.substring,
          pattern: pathPattern,
        );
      }

      return AdblockRule(
        rawRule: line,
        type: AdblockRuleType.domainSuffix,
        pattern: target,
      );
    }

    final sanitized = line
        .replaceAll('^', '')
        .replaceAll('*', '')
        .replaceAll('|', '')
        .toLowerCase();
    if (sanitized.isEmpty) {
      return null;
    }

    return AdblockRule(
      rawRule: line,
      type: AdblockRuleType.substring,
      pattern: sanitized,
    );
  }

  bool matches(Uri uri) {
    switch (type) {
      case AdblockRuleType.domainSuffix:
        return HostMatcher.matches(uri.host, <String>[pattern, '*.$pattern']);
      case AdblockRuleType.substring:
        return uri.toString().toLowerCase().contains(pattern);
    }
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'rawRule': rawRule,
      'type': type.name,
      'pattern': pattern,
    };
  }
}
