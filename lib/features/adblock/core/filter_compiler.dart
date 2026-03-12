import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/adblock_rule.dart';

class FilterCompilationResult {
  const FilterCompilationResult({
    required this.rules,
    required this.revision,
    required this.parsedLines,
    required this.ignoredLines,
  });

  final List<AdblockRule> rules;
  final String revision;
  final int parsedLines;
  final int ignoredLines;
}

class FilterCompiler {
  const FilterCompiler();

  String computeRevision(Iterable<String> rawLines) {
    final normalizedLines = <String>[];
    for (final rawLine in rawLines) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }
      normalizedLines.add(line);
    }
    return sha256.convert(utf8.encode(normalizedLines.join('\n'))).toString();
  }

  FilterCompilationResult compile(Iterable<String> rawLines) {
    final rules = <AdblockRule>[];
    var parsedLines = 0;
    var ignoredLines = 0;
    final normalizedLines = <String>[];

    for (final rawLine in rawLines) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }
      normalizedLines.add(line);
      parsedLines += 1;
      final parsed = AdblockRule.parse(line);
      if (parsed == null) {
        ignoredLines += 1;
        continue;
      }
      rules.add(parsed);
    }

    final revision = sha256
        .convert(utf8.encode(normalizedLines.join('\n')))
        .toString();

    return FilterCompilationResult(
      rules: List<AdblockRule>.unmodifiable(rules),
      revision: revision,
      parsedLines: parsedLines,
      ignoredLines: ignoredLines,
    );
  }
}
