import 'package:flutter/services.dart';

import 'models/adblock_rule.dart';

class FilterListLoader {
  const FilterListLoader({required this.assetPath});

  final String assetPath;

  Future<List<AdblockRule>> load() async {
    final raw = await rootBundle.loadString(assetPath);
    final rules = <AdblockRule>[];

    for (final line in raw.split(RegExp(r'\r?\n'))) {
      final parsed = AdblockRule.parse(line);
      if (parsed != null) {
        rules.add(parsed);
      }
    }

    return List<AdblockRule>.unmodifiable(rules);
  }
}
