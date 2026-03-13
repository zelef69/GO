import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/adblock/filters/filter_parser.dart';
import 'package:go_play/features/adblock/filters/rule_models.dart';
import 'package:go_play/features/adblock/filters/rule_normalizer.dart';

void main() {
  group('RuleNormalizer', () {
    const parser = FilterParser();
    const normalizer = RuleNormalizer();

    test('normalizes domains/resource types and preserves explicit actions', () {
      final parsed = parser.parse(const <String>[
        r'@@||Ads.Example.com^$script,redirect=noopjs,domain=Example.COM',
        r'||tracker.example.com/pixel$IMAGE,third-party,rewrite=https://Example.com/Blank',
      ]);

      final normalized = normalizer.normalize(parsed);
      expect(normalized.networkRules.length, 2);

      final exception = normalized.networkRules.first;
      final rewrite = normalized.networkRules.last;

      expect(exception.action, NetworkRuleAction.exception);
      expect(exception.isException, isTrue);
      expect(exception.redirectTarget, isNull);
      expect(exception.includeDomains.contains('example.com'), isTrue);

      expect(rewrite.action, NetworkRuleAction.rewrite);
      expect(rewrite.isException, isFalse);
      expect(rewrite.resourceTypes.contains('image'), isTrue);
      expect(rewrite.thirdPartyOnly, isTrue);
      expect(rewrite.rewriteTarget, 'https://Example.com/Blank');
    });
  });
}
