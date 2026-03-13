import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/adblock/filters/filter_parser.dart';

void main() {
  group('FilterParser', () {
    const parser = FilterParser();

    test('parses network rules with options and exception', () {
      final parsed = parser.parse(const <String>[
        r'||ads.example.com^$script,third-party',
        r'@@||ads.example.com^$domain=example.com',
      ]);

      expect(parsed.networkRules.length, 2);
      final blockRule = parsed.networkRules.first;
      final exceptionRule = parsed.networkRules.last;

      expect(blockRule.isException, isFalse);
      expect(blockRule.hostAnchored, isTrue);
      expect(blockRule.resourceTypes.contains('script'), isTrue);
      expect(blockRule.thirdPartyOnly, isTrue);

      expect(exceptionRule.isException, isTrue);
      expect(exceptionRule.includeDomains.contains('example.com'), isTrue);
    });

    test('parses cosmetic hide and cosmetic exception', () {
      final parsed = parser.parse(const <String>[
        'example.com##.ad-banner',
        'example.com#@#.ad-banner',
      ]);

      expect(parsed.cosmeticRules.length, 2);
      expect(parsed.cosmeticRules.first.isException, isFalse);
      expect(parsed.cosmeticRules.last.isException, isTrue);
      expect(parsed.cosmeticRules.first.selector, '.ad-banner');
    });

    test('parses scriptlet rules from +js and raw script', () {
      final parsed = parser.parse(const <String>[
        'example.com##+js(set-constant, canRunAds, false)',
        r'example.com#$#window.__adblocked = true;',
      ]);

      expect(parsed.scriptInjectionRules.length, 2);
      expect(parsed.scriptInjectionRules.first.scriptletName, 'set-constant');
      expect(parsed.scriptInjectionRules.first.arguments, <String>[
        'canRunAds',
        'false',
      ]);
      expect(
        parsed.scriptInjectionRules.last.rawScript,
        'window.__adblocked = true;',
      );
    });

    test('parses redirect and rewrite network actions', () {
      final parsed = parser.parse(const <String>[
        r'||ads.example.com/banner.js$script,redirect=noopjs',
        r'||tracker.example.com/pixel$rewrite=https://example.com/blank',
      ]);

      expect(parsed.networkRules.length, 2);
      final redirectRule = parsed.networkRules.first;
      final rewriteRule = parsed.networkRules.last;

      expect(redirectRule.isRedirect, isTrue);
      expect(redirectRule.redirectTarget, 'noopjs');
      expect(redirectRule.isException, isFalse);

      expect(rewriteRule.isRewrite, isTrue);
      expect(rewriteRule.rewriteTarget, 'https://example.com/blank');
      expect(rewriteRule.isException, isFalse);
    });
  });
}
