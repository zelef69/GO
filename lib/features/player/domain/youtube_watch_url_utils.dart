import '../../../shared/utils/host_matcher.dart';

class YouTubeWatchUrlUtils {
  const YouTubeWatchUrlUtils._();

  static const List<String> _watchHosts = <String>[
    'youtube.com',
    '*.youtube.com',
    'youtu.be',
    '*.youtu.be',
  ];

  static Uri? normalizeUrl(Uri? uri) {
    if (uri == null) {
      return null;
    }
    final normalizedScheme = uri.scheme.toLowerCase();
    if (normalizedScheme != 'http' && normalizedScheme != 'https') {
      return null;
    }
    return uri.replace(
      scheme: 'https',
      host: uri.host.toLowerCase(),
      fragment: '',
    );
  }

  static bool isAllowedUrl(Uri? uri) {
    final normalized = normalizeUrl(uri);
    if (normalized == null) {
      return false;
    }
    return HostMatcher.matches(normalized.host, _watchHosts);
  }

  static bool isYouTubeWatchUrl(Uri? uri) {
    return extractVideoId(uri) != null;
  }

  static String? extractVideoId(Uri? uri) {
    final normalized = normalizeUrl(uri);
    if (normalized == null) {
      return null;
    }

    final host = normalized.host;
    final pathSegments = normalized.pathSegments
        .where((segment) => segment.trim().isNotEmpty)
        .toList(growable: false);

    if (HostMatcher.matches(host, <String>['youtu.be', '*.youtu.be'])) {
      if (pathSegments.isEmpty) {
        return null;
      }
      return _sanitizeVideoId(pathSegments.first);
    }

    if (!HostMatcher.matches(host, <String>['youtube.com', '*.youtube.com'])) {
      return null;
    }

    if (normalized.path.toLowerCase() == '/watch') {
      return _sanitizeVideoId(normalized.queryParameters['v']);
    }

    if (pathSegments.length >= 2) {
      final section = pathSegments.first.toLowerCase();
      if (section == 'shorts' || section == 'embed' || section == 'live') {
        return _sanitizeVideoId(pathSegments[1]);
      }
    }

    return null;
  }

  static String? _sanitizeVideoId(String? input) {
    if (input == null) {
      return null;
    }
    final trimmed = input.trim();
    if (trimmed.length < 6) {
      return null;
    }
    final candidate = trimmed.split('?').first.split('&').first;
    if (candidate.isEmpty) {
      return null;
    }
    return candidate;
  }
}
