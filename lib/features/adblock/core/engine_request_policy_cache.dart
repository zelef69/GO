import 'dart:collection';

import 'request_runtime_models.dart';

class EngineRequestDecisionCache {
  EngineRequestDecisionCache({required this.limit, required this.ttl});

  final int limit;
  final Duration ttl;
  final LinkedHashMap<String, _EngineRequestDecisionCacheEntry> _entries =
      LinkedHashMap<String, _EngineRequestDecisionCacheEntry>();

  void clear() {
    _entries.clear();
  }

  AdblockDecision? read(String key) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final entry = _entries.remove(key);
    if (entry == null) {
      return null;
    }
    if (entry.expiresAtMs <= now) {
      return null;
    }
    _entries[key] = entry;
    return AdblockDecision(
      blocked: entry.blocked,
      reason: entry.reason,
      matchedRule: entry.matchedRule,
      redirectDataUrl: entry.redirectDataUrl,
      rewrittenUrl: entry.rewrittenUrl,
      fromCache: true,
    );
  }

  void write(String key, AdblockDecision decision) {
    _entries.remove(key);
    _entries[key] = _EngineRequestDecisionCacheEntry(
      blocked: decision.blocked,
      reason: decision.reason,
      matchedRule: decision.matchedRule,
      redirectDataUrl: decision.redirectDataUrl,
      rewrittenUrl: decision.rewrittenUrl,
      expiresAtMs: DateTime.now().add(ttl).millisecondsSinceEpoch,
    );
    if (_entries.length > limit) {
      _entries.remove(_entries.keys.first);
    }
  }
}

class _EngineRequestDecisionCacheEntry {
  const _EngineRequestDecisionCacheEntry({
    required this.blocked,
    required this.reason,
    required this.matchedRule,
    required this.redirectDataUrl,
    required this.rewrittenUrl,
    required this.expiresAtMs,
  });

  final bool blocked;
  final String reason;
  final String? matchedRule;
  final String? redirectDataUrl;
  final String? rewrittenUrl;
  final int expiresAtMs;
}
