class LearnedSignatureMatchResult {
  const LearnedSignatureMatchResult({
    required this.matched,
    required this.sigHash,
    required this.reason,
    required this.confidence,
  });

  const LearnedSignatureMatchResult.noMatch()
    : matched = false,
      sigHash = '',
      reason = '',
      confidence = 0;

  final bool matched;
  final String sigHash;
  final String reason;
  final double confidence;
}
