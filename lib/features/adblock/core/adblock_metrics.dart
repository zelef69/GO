class AdblockMetricsSnapshot {
  const AdblockMetricsSnapshot({
    required this.blockedRequests,
    required this.allowedRequests,
    required this.lastMatchedRule,
    required this.lastDecisionReason,
    required this.lastEvaluationMs,
    required this.currentPageHost,
    required this.pageBlockedRequests,
    required this.pageAllowedRequests,
  });

  final int blockedRequests;
  final int allowedRequests;
  final String? lastMatchedRule;
  final String? lastDecisionReason;
  final int lastEvaluationMs;
  final String currentPageHost;
  final int pageBlockedRequests;
  final int pageAllowedRequests;
}

class AdblockMetricsCollector {
  int _blockedRequests = 0;
  int _allowedRequests = 0;
  String? _lastMatchedRule;
  String? _lastDecisionReason;
  int _lastEvaluationMs = 0;
  String _currentPageHost = '';
  int _pageBlockedRequests = 0;
  int _pageAllowedRequests = 0;

  void onPageChanged(Uri? pageUri) {
    final host = pageUri?.host.toLowerCase() ?? '';
    if (host == _currentPageHost) {
      return;
    }
    _currentPageHost = host;
    _pageBlockedRequests = 0;
    _pageAllowedRequests = 0;
  }

  void onDecision({
    required bool blocked,
    required int elapsedMs,
    String? matchedRule,
    required String reason,
  }) {
    if (blocked) {
      _blockedRequests += 1;
      _pageBlockedRequests += 1;
    } else {
      _allowedRequests += 1;
      _pageAllowedRequests += 1;
    }
    _lastMatchedRule = matchedRule;
    _lastDecisionReason = reason;
    _lastEvaluationMs = elapsedMs;
  }

  AdblockMetricsSnapshot snapshot() {
    return AdblockMetricsSnapshot(
      blockedRequests: _blockedRequests,
      allowedRequests: _allowedRequests,
      lastMatchedRule: _lastMatchedRule,
      lastDecisionReason: _lastDecisionReason,
      lastEvaluationMs: _lastEvaluationMs,
      currentPageHost: _currentPageHost,
      pageBlockedRequests: _pageBlockedRequests,
      pageAllowedRequests: _pageAllowedRequests,
    );
  }

  void reset() {
    _blockedRequests = 0;
    _allowedRequests = 0;
    _lastMatchedRule = null;
    _lastDecisionReason = null;
    _lastEvaluationMs = 0;
    _currentPageHost = '';
    _pageBlockedRequests = 0;
    _pageAllowedRequests = 0;
  }
}
