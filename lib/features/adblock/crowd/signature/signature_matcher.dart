import '../models/learned_signature.dart';
import '../models/learned_signature_match_result.dart';

class SignatureMatcher {
  const SignatureMatcher();

  LearnedSignatureMatchResult match({
    required Iterable<LearnedSignature> signatures,
    required Uri uri,
    required String resourceType,
    required Uri? sourceUrl,
    required bool adShowing,
    required bool playbackStalled,
    required int nowMs,
  }) {
    if (playbackStalled) {
      return const LearnedSignatureMatchResult.noMatch();
    }

    final normalizedResourceType = resourceType.trim().toLowerCase();
    final requestHost = uri.host.trim().toLowerCase();
    final requestPath = uri.path.trim().toLowerCase();
    final sourceHost = (sourceUrl?.host ?? '').trim().toLowerCase();
    final queryKeys = uri.queryParameters.keys
        .map((entry) => entry.trim().toLowerCase())
        .where((entry) => entry.isNotEmpty)
        .toSet();

    for (final signature in signatures) {
      if (!signature.isActiveAt(nowMs)) {
        continue;
      }
      if (signature.resourceType != normalizedResourceType) {
        continue;
      }
      if (signature.requireAdSignal && !adShowing) {
        continue;
      }
      if (!_hostMatches(signature.hostPattern, requestHost)) {
        continue;
      }
      if (!_pathMatches(signature.pathPattern, requestPath)) {
        continue;
      }
      if (signature.sourceHost.isNotEmpty &&
          !_sourceHostMatches(signature.sourceHost, sourceHost)) {
        continue;
      }
      if (signature.markerKeys.isEmpty) {
        continue;
      }
      if (!_hasMarkerIntersection(signature.markerKeys, queryKeys)) {
        continue;
      }
      return LearnedSignatureMatchResult(
        matched: true,
        sigHash: signature.sigHash,
        reason: 'crowd_learned_signature',
        confidence: signature.confidence,
      );
    }

    return const LearnedSignatureMatchResult.noMatch();
  }

  bool _hostMatches(String pattern, String requestHost) {
    if (pattern.isEmpty || requestHost.isEmpty) {
      return false;
    }
    if (pattern.startsWith('*.')) {
      final suffix = pattern.substring(1); // includes leading dot
      final base = pattern.substring(2);
      return requestHost == base || requestHost.endsWith(suffix);
    }
    return requestHost == pattern;
  }

  bool _pathMatches(String pattern, String requestPath) {
    final normalizedPattern = pattern.trim().toLowerCase();
    final normalizedPath = requestPath.trim().toLowerCase();
    if (normalizedPattern.isEmpty) {
      return true;
    }
    if (normalizedPath.isEmpty) {
      return normalizedPattern == '/';
    }
    if (normalizedPattern == '/') {
      return true;
    }
    return normalizedPath.startsWith(normalizedPattern);
  }

  bool _sourceHostMatches(String pattern, String sourceHost) {
    if (pattern.isEmpty) {
      return true;
    }
    if (sourceHost.isEmpty) {
      return false;
    }
    if (pattern.startsWith('*.')) {
      final suffix = pattern.substring(1);
      final base = pattern.substring(2);
      return sourceHost == base || sourceHost.endsWith(suffix);
    }
    return sourceHost == pattern;
  }

  bool _hasMarkerIntersection(
    List<String> signatureKeys,
    Set<String> queryKeys,
  ) {
    for (final key in signatureKeys) {
      if (queryKeys.contains(key)) {
        return true;
      }
    }
    return false;
  }
}
