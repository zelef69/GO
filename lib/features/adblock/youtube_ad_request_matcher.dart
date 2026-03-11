import '../../shared/utils/host_matcher.dart';

class YouTubeAdRequestMatcher {
  const YouTubeAdRequestMatcher._();

  static const List<String> knownAdHostPatterns = <String>[
    'doubleclick.net',
    '*.doubleclick.net',
    'googlesyndication.com',
    '*.googlesyndication.com',
    'googleadservices.com',
    '*.googleadservices.com',
    'adservice.google.com',
    '*.adservice.google.com',
    'pagead2.googlesyndication.com',
    'pubads.g.doubleclick.net',
    'securepubads.g.doubleclick.net',
  ];

  static const List<String> _youtubeAdPathTokens = <String>[
    '/api/stats/ads',
    '/api/stats/ad',
    '/api/stats/atr',
    '/pagead/',
    '/get_midroll_info',
    '/ptracking',
    '/ad_break',
    '/youtubei/v1/player/ad_break',
    '/youtubei/v1/ad',
  ];

  static const List<String> _googleVideoAdQueryKeys = <String>[
    'oad',
    'adformat',
    'ad_type',
    'ad_preroll',
    'dclk_video_ads',
    'ad3_module',
    'videoadid',
    'adtag',
    'ad_tag',
    'ad_debug',
    'adsid',
    'ad_host_tier',
    'ad_flags',
  ];

  static bool _containsAnyQueryKeyInRawQuery(
    String rawQuery,
    List<String> keys,
  ) {
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

  static bool _pathContainsAnyToken(String path, List<String> tokens) {
    for (final token in tokens) {
      if (path.contains(token)) {
        return true;
      }
    }
    return false;
  }

  static bool matches(Uri uri) {
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();

    if (HostMatcher.matches(host, knownAdHostPatterns)) {
      return true;
    }

    if (HostMatcher.matches(host, <String>['youtube.com', '*.youtube.com'])) {
      if (_pathContainsAnyToken(path, _youtubeAdPathTokens)) {
        return true;
      }
    }

    if (HostMatcher.matches(host, <String>[
      'googlevideo.com',
      '*.googlevideo.com',
    ])) {
      final isVideoPlaybackPath = path.contains('/videoplayback');
      if (isVideoPlaybackPath &&
          _containsAnyQueryKeyInRawQuery(uri.query, _googleVideoAdQueryKeys)) {
        return true;
      }
    }

    return false;
  }
}
