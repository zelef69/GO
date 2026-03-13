import '../core/types.dart';
import '../utils/tokenize.dart';

class RequestInterceptor {
  const RequestInterceptor();

  RequestContext normalize({
    required Uri url,
    required String resourceType,
    Uri? frameUrl,
    Uri? topLevelUrl,
    String method = 'GET',
    Map<String, dynamic>? headers,
  }) {
    final normalizedHeaders = _normalizeHeaders(headers);
    final effectiveTopLevel = topLevelUrl ?? frameUrl;
    final hostname = url.host.toLowerCase();
    final domain = registrableDomainFromHost(hostname);
    final frameHostname = frameUrl?.host.toLowerCase() ?? '';
    final topLevelHostname = effectiveTopLevel?.host.toLowerCase() ?? '';
    final topDomain = effectiveTopLevel == null
        ? ''
        : registrableDomainFromHost(effectiveTopLevel.host);
    final isThirdParty =
        domain.isNotEmpty && topDomain.isNotEmpty && domain != topDomain;
    final isTopLevel =
        frameUrl == null &&
        (effectiveTopLevel == null ||
            _sameRequestUrl(url, effectiveTopLevel));
    return RequestContext(
      url: url,
      hostname: hostname,
      domain: domain,
      path: url.path,
      query: url.query,
      resourceType: resourceType.trim().toLowerCase(),
      frameUrl: frameUrl,
      topLevelUrl: effectiveTopLevel,
      frameHostname: frameHostname,
      topLevelHostname: topLevelHostname,
      method: method.trim().isEmpty ? 'GET' : method.trim().toUpperCase(),
      headers: normalizedHeaders,
      isThirdParty: isThirdParty,
      isTopLevel: isTopLevel,
    );
  }

  Uri? sourceUriFromHeaders(Map<String, dynamic>? headers) {
    final normalized = _normalizeHeaders(headers);
    final referer = normalized['referer'] ?? normalized['referrer'] ?? '';
    final value = referer.trim();
    if (value.isEmpty) {
      return null;
    }
    return Uri.tryParse(value);
  }

  String classifyResourceType({
    required Uri url,
    required bool isMainFrame,
    Map<String, dynamic>? headers,
  }) {
    if (isMainFrame) {
      return 'document';
    }
    final normalizedHeaders = _normalizeHeaders(headers);
    final secFetchDest = (normalizedHeaders['sec-fetch-dest'] ?? '')
        .trim()
        .toLowerCase();
    switch (secFetchDest) {
      case 'script':
        return 'script';
      case 'style':
        return 'stylesheet';
      case 'image':
        return 'image';
      case 'font':
        return 'font';
      case 'video':
      case 'audio':
      case 'track':
        return 'media';
      case 'iframe':
      case 'frame':
        return 'subdocument';
      case 'document':
        return 'document';
      case 'empty':
        return 'xmlhttprequest';
    }
    final path = url.path.toLowerCase();
    final host = url.host.toLowerCase();
    final isGoogleVideo =
        (host == 'googlevideo.com' || host.endsWith('.googlevideo.com')) &&
        path.contains('/videoplayback');
    if (isGoogleVideo) {
      return 'media';
    }
    if (path.endsWith('.js') || path.contains('/base.js')) {
      return 'script';
    }
    if (path.endsWith('.css')) {
      return 'stylesheet';
    }
    if (path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png') ||
        path.endsWith('.webp') ||
        path.endsWith('.gif') ||
        path.endsWith('.svg')) {
      return 'image';
    }
    if (path.endsWith('.woff') ||
        path.endsWith('.woff2') ||
        path.endsWith('.ttf')) {
      return 'font';
    }
    if (path.endsWith('.mp4') ||
        path.endsWith('.webm') ||
        path.endsWith('.m3u8') ||
        path.endsWith('.m4s') ||
        path.endsWith('.ts')) {
      return 'media';
    }
    return 'other';
  }

  Map<String, String> _normalizeHeaders(Map<String, dynamic>? headers) {
    if (headers == null || headers.isEmpty) {
      return const <String, String>{};
    }
    final normalized = <String, String>{};
    for (final entry in headers.entries) {
      final key = entry.key.toLowerCase().trim();
      if (key.isEmpty) {
        continue;
      }
      final value = entry.value?.toString() ?? '';
      normalized[key] = value;
    }
    return normalized;
  }

  bool _sameRequestUrl(Uri left, Uri right) {
    return left.scheme.toLowerCase() == right.scheme.toLowerCase() &&
        left.host.toLowerCase() == right.host.toLowerCase() &&
        left.path == right.path &&
        left.query == right.query;
  }
}
