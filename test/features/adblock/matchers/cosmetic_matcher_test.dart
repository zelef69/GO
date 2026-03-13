import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/adblock/core/types.dart';
import 'package:go_play/features/adblock/filters/filter_compiler.dart';
import 'package:go_play/features/adblock/filters/filter_parser.dart';
import 'package:go_play/features/adblock/matchers/cosmetic_matcher.dart';

void main() {
  group('CosmeticMatcher', () {
    const parser = FilterParser();
    const compiler = IndexedFilterCompiler();
    const matcher = CosmeticMatcher();

    test('applies domain-scoped hide rules and cosmetic exceptions', () {
      const lines = <String>[
        '##.global-ad',
        'example.com##.domain-ad',
        'example.com#@#.domain-ad',
      ];
      final parsed = parser.parse(lines);
      final compiled = compiler.compile(parsed: parsed, rawLines: lines);
      final context = PageContext(
        url: Uri.parse('https://www.example.com/watch'),
        hostname: 'www.example.com',
        domain: 'example.com',
        topLevelUrl: Uri.parse('https://www.example.com/watch'),
        headers: <String, String>{},
      );

      final rules = matcher.match(context, compiled);

      expect(rules.selectors.contains('.global-ad'), isTrue);
      expect(rules.selectors.contains('.domain-ad'), isFalse);
      expect(rules.exceptions.contains('.domain-ad'), isTrue);
    });

    test('does not apply scoped cosmetic rules for other domains', () {
      const lines = <String>['example.com##.domain-ad'];
      final parsed = parser.parse(lines);
      final compiled = compiler.compile(parsed: parsed, rawLines: lines);
      final context = PageContext(
        url: Uri.parse('https://news.other.com/article'),
        hostname: 'news.other.com',
        domain: 'other.com',
        topLevelUrl: Uri.parse('https://news.other.com/article'),
        headers: <String, String>{},
      );

      final rules = matcher.match(context, compiled);

      expect(rules.selectors, isEmpty);
      expect(rules.exceptions, isEmpty);
    });
  });
}
