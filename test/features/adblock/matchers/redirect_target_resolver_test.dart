import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/adblock/core/types.dart';
import 'package:go_play/features/adblock/matchers/redirect_target_resolver.dart';

void main() {
  group('RedirectTargetResolver', () {
    const resolver = RedirectTargetResolver();
    const rewriteResolver = RewriteTargetResolver();
    final context = RequestContext(
      url: Uri.parse('https://ads.example.com/banner.js'),
      hostname: 'ads.example.com',
      domain: 'example.com',
      path: '/banner.js',
      query: '',
      resourceType: 'script',
      frameUrl: Uri.parse('https://www.example.com/watch'),
      topLevelUrl: Uri.parse('https://www.example.com/watch'),
      frameHostname: 'www.example.com',
      topLevelHostname: 'www.example.com',
      method: 'GET',
      headers: const <String, String>{},
      isThirdParty: false,
      isTopLevel: false,
    );

    test('resolves common redirect aliases to data URLs', () {
      final resolved = resolver.resolve('noopjs', context: context);

      expect(resolved, isNotNull);
      expect(resolved, startsWith('data:'));
    });

    test('resolves relative rewrite targets against source context', () {
      final resolved = rewriteResolver.resolve('/blank', context: context);

      expect(resolved, 'https://www.example.com/blank');
    });
  });
}
