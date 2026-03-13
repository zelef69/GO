class EngineRequestQueryUtils {
  const EngineRequestQueryUtils({
    required this.hardAdQueryKeys,
    required this.aggressiveGuardQueryKeys,
    required this.aggressiveGuardValueTokens,
  });

  final List<String> hardAdQueryKeys;
  final List<String> aggressiveGuardQueryKeys;
  final List<String> aggressiveGuardValueTokens;

  bool containsAnyQueryKeyInRawQuery(String rawQuery, List<String> keys) {
    if (rawQuery.isEmpty) {
      return false;
    }
    final normalizedQuery = '&${rawQuery.toLowerCase()}&';
    for (final key in keys) {
      if (normalizedQuery.contains('&$key=') ||
          normalizedQuery.contains('&$key&')) {
        return true;
      }
    }
    return false;
  }

  int countQueryKeyHitsInRawQuery(
    String rawQuery,
    List<String> keys, {
    int maxHits = 999,
  }) {
    if (rawQuery.isEmpty || keys.isEmpty || maxHits <= 0) {
      return 0;
    }
    final normalizedQuery = '&${rawQuery.toLowerCase()}&';
    var hits = 0;
    for (final key in keys) {
      if (normalizedQuery.contains('&$key=') ||
          normalizedQuery.contains('&$key&')) {
        hits += 1;
        if (hits >= maxHits) {
          return hits;
        }
      }
    }
    return hits;
  }

  bool containsAllQueryKeysInRawQuery(String rawQuery, List<String> keys) {
    if (rawQuery.isEmpty || keys.isEmpty) {
      return false;
    }
    final normalizedQuery = '&${rawQuery.toLowerCase()}&';
    for (final key in keys) {
      final normalizedKey = key.trim().toLowerCase();
      if (normalizedKey.isEmpty) {
        continue;
      }
      if (!(normalizedQuery.contains('&$normalizedKey=') ||
          normalizedQuery.contains('&$normalizedKey&'))) {
        return false;
      }
    }
    return true;
  }

  bool containsAdLikeQueryKey(String rawQuery) {
    if (rawQuery.isEmpty) {
      return false;
    }
    for (final segment in rawQuery.split('&')) {
      if (segment.isEmpty) {
        continue;
      }
      final separator = segment.indexOf('=');
      final rawKey = separator == -1
          ? segment
          : segment.substring(0, separator);
      final key = safeDecodeQueryComponent(rawKey).toLowerCase();
      if (isAdLikeQueryKey(key)) {
        return true;
      }
    }
    return false;
  }

  bool containsAdLikeQueryValue(String rawQuery) {
    if (rawQuery.isEmpty) {
      return false;
    }
    for (final segment in rawQuery.split('&')) {
      if (segment.isEmpty) {
        continue;
      }
      final separator = segment.indexOf('=');
      if (separator == -1) {
        continue;
      }
      final rawValue = segment.substring(separator + 1);
      final value = safeDecodeQueryComponent(rawValue).toLowerCase();
      if (isAdLikeQueryValue(value)) {
        return true;
      }
    }
    return false;
  }

  bool isAdLikeQueryKey(String key) {
    if (key.isEmpty) {
      return false;
    }
    if (key == 'oad' || key == 'ad') {
      return true;
    }
    if (hardAdQueryKeys.contains(key)) {
      return true;
    }
    if (key.startsWith('dclk_')) {
      return true;
    }
    if (key.startsWith('videoad') ||
        key.endsWith('adid') ||
        key.endsWith('adsid')) {
      return true;
    }
    return false;
  }

  bool isAdLikeQueryValue(String value) {
    if (value.isEmpty) {
      return false;
    }
    for (final marker in aggressiveGuardValueTokens) {
      if (value.contains(marker)) {
        return true;
      }
    }
    return false;
  }

  bool containsQueryKeyWithValuePrefix(
    String rawQuery, {
    required String key,
    required String valuePrefix,
  }) {
    if (rawQuery.isEmpty) {
      return false;
    }
    final normalizedKey = key.trim().toLowerCase();
    final normalizedValuePrefix = valuePrefix.trim().toLowerCase();
    if (normalizedKey.isEmpty || normalizedValuePrefix.isEmpty) {
      return false;
    }
    for (final segment in rawQuery.split('&')) {
      if (segment.isEmpty) {
        continue;
      }
      final separator = segment.indexOf('=');
      final rawKey = separator == -1
          ? segment
          : segment.substring(0, separator);
      final decodedKey = safeDecodeQueryComponent(rawKey).toLowerCase();
      if (decodedKey != normalizedKey) {
        continue;
      }
      if (separator == -1) {
        return false;
      }
      final rawValue = segment.substring(separator + 1);
      final decodedValue = safeDecodeQueryComponent(rawValue).toLowerCase();
      return decodedValue.startsWith(normalizedValuePrefix);
    }
    return false;
  }

  bool containsQueryKeyWithAnyValue(
    String rawQuery, {
    required String key,
    required List<String> candidateValues,
  }) {
    if (rawQuery.isEmpty || candidateValues.isEmpty) {
      return false;
    }
    final normalizedKey = key.trim().toLowerCase();
    if (normalizedKey.isEmpty) {
      return false;
    }
    final normalizedValues = candidateValues
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (normalizedValues.isEmpty) {
      return false;
    }

    for (final segment in rawQuery.split('&')) {
      if (segment.isEmpty) {
        continue;
      }
      final separator = segment.indexOf('=');
      final rawKey = separator == -1
          ? segment
          : segment.substring(0, separator);
      final decodedKey = safeDecodeQueryComponent(rawKey).toLowerCase();
      if (decodedKey != normalizedKey || separator == -1) {
        continue;
      }
      final rawValue = segment.substring(separator + 1);
      final decodedValue = safeDecodeQueryComponent(rawValue).toLowerCase();
      if (normalizedValues.contains(decodedValue)) {
        return true;
      }
    }
    return false;
  }

  bool containsQueryKeyValueContainingAllTokens(
    String rawQuery, {
    required String key,
    required List<String> tokens,
  }) {
    if (rawQuery.isEmpty || tokens.isEmpty) {
      return false;
    }
    final normalizedKey = key.trim().toLowerCase();
    if (normalizedKey.isEmpty) {
      return false;
    }
    final normalizedTokens = tokens
        .map((token) => token.trim().toLowerCase())
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    if (normalizedTokens.isEmpty) {
      return false;
    }

    for (final segment in rawQuery.split('&')) {
      if (segment.isEmpty) {
        continue;
      }
      final separator = segment.indexOf('=');
      if (separator == -1) {
        continue;
      }
      final rawKey = segment.substring(0, separator);
      final decodedKey = safeDecodeQueryComponent(rawKey).toLowerCase();
      if (decodedKey != normalizedKey) {
        continue;
      }
      final rawValue = segment.substring(separator + 1);
      final decodedValue = safeDecodeQueryComponent(rawValue).toLowerCase();
      var allFound = true;
      for (final token in normalizedTokens) {
        if (!decodedValue.contains(token)) {
          allFound = false;
          break;
        }
      }
      if (allFound) {
        return true;
      }
    }
    return false;
  }

  String safeDecodeQueryComponent(String value) {
    try {
      return Uri.decodeQueryComponent(value);
    } catch (_) {
      return value;
    }
  }

  List<String> adLikeMarkerHints(String rawQuery, {int limit = 10}) {
    if (rawQuery.isEmpty) {
      return const <String>[];
    }
    final hints = <String>[];
    final seen = <String>{};
    for (final segment in rawQuery.split('&')) {
      if (segment.isEmpty) {
        continue;
      }
      final separator = segment.indexOf('=');
      final rawKey = separator == -1
          ? segment
          : segment.substring(0, separator);
      final key = safeDecodeQueryComponent(rawKey).toLowerCase();
      if (key.isEmpty) {
        continue;
      }
      final rawValue = separator == -1 ? '' : segment.substring(separator + 1);
      final value = safeDecodeQueryComponent(rawValue).toLowerCase();
      final keyAdLike =
          isAdLikeQueryKey(key) || aggressiveGuardQueryKeys.contains(key);
      final valueAdLike = isAdLikeQueryValue(value);
      if (!keyAdLike && !valueAdLike) {
        continue;
      }
      final compactValue = value.isEmpty
          ? ''
          : '=(${clipForLog(value, maxChars: 42)})';
      final hint = '$key$compactValue';
      if (!seen.add(hint)) {
        continue;
      }
      hints.add(hint);
      if (hints.length >= limit) {
        break;
      }
    }
    return hints;
  }

  String queryKeysSummary(String rawQuery, {int limit = 10}) {
    if (rawQuery.isEmpty) {
      return 'none';
    }
    final keys = <String>[];
    final seen = <String>{};
    var truncated = false;
    for (final segment in rawQuery.split('&')) {
      if (segment.isEmpty) {
        continue;
      }
      final separator = segment.indexOf('=');
      final rawKey = separator == -1
          ? segment
          : segment.substring(0, separator);
      final key = safeDecodeQueryComponent(rawKey).toLowerCase();
      if (key.isEmpty || !seen.add(key)) {
        continue;
      }
      if (keys.length >= limit) {
        truncated = true;
        break;
      }
      keys.add(key);
    }
    if (keys.isEmpty) {
      return 'none';
    }
    if (truncated) {
      return '${keys.join(',')},+more';
    }
    return keys.join(',');
  }

  String clipForLog(String value, {required int maxChars}) {
    if (value.length <= maxChars) {
      return value;
    }
    return '${value.substring(0, maxChars)}...';
  }
}
