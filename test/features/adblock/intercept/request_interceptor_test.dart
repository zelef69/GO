import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/adblock/intercept/request_interceptor.dart';

void main() {
  group('RequestInterceptor', () {
    const interceptor = RequestInterceptor();

    test('extracts source uri from referer headers', () {
      final source = interceptor.sourceUriFromHeaders(const <String, String>{
        'Referer': 'https://m.youtube.com/watch?v=abc',
      });

      expect(source, isNotNull);
      expect(source!.host, 'm.youtube.com');
    });

    test('classifies resource type from sec-fetch-dest and url fallback', () {
      final scriptType = interceptor.classifyResourceType(
        url: Uri.parse('https://cdn.example.com/app.js'),
        isMainFrame: false,
        headers: const <String, String>{'Sec-Fetch-Dest': 'script'},
      );
      final mediaType = interceptor.classifyResourceType(
        url: Uri.parse(
          'https://rr2---sn-abc.googlevideo.com/videoplayback?id=1',
        ),
        isMainFrame: false,
      );

      expect(scriptType, 'script');
      expect(mediaType, 'media');
    });

    test('normalizes request context with third-party signal', () {
      final context = interceptor.normalize(
        url: Uri.parse('https://ads.example.net/tracker.js?slot=pre'),
        resourceType: 'script',
        frameUrl: Uri.parse('https://news.example.com/article'),
        topLevelUrl: Uri.parse('https://news.example.com/article'),
        method: 'get',
        headers: const <String, String>{'X-Test': '1'},
      );

      expect(context.hostname, 'ads.example.net');
      expect(context.domain, 'example.net');
      expect(context.resourceType, 'script');
      expect(context.query, 'slot=pre');
      expect(context.frameHostname, 'news.example.com');
      expect(context.topLevelHostname, 'news.example.com');
      expect(context.method, 'GET');
      expect(context.isThirdParty, isTrue);
      expect(context.isTopLevel, isFalse);
      expect(context.headers['x-test'], '1');
    });

    test('marks top-level navigation context', () {
      final url = Uri.parse('https://m.youtube.com/watch?v=abc');
      final context = interceptor.normalize(
        url: url,
        resourceType: 'document',
        topLevelUrl: url,
      );

      expect(context.isTopLevel, isTrue);
      expect(context.isThirdParty, isFalse);
      expect(context.topLevelHostname, 'm.youtube.com');
    });
  });
}
