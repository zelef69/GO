import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/adblock/filters/filter_compiler.dart';
import 'package:go_play/features/adblock/filters/filter_parser.dart';
import 'package:go_play/features/adblock/intercept/request_interceptor.dart';
import 'package:go_play/features/adblock/matchers/request_matcher.dart';

void main() {
  group('IndexedFilterCompiler + RequestMatcher', () {
    const parser = FilterParser();
    const compiler = IndexedFilterCompiler();
    const matcher = RequestMatcher();
    const interceptor = RequestInterceptor();

    test('exception rule overrides block rule', () {
      const lines = <String>[
        r'||ads.target.com/banner.js$script',
        r'@@||ads.target.com/banner.js$domain=example.com',
      ];
      final parsed = parser.parse(lines);
      final compiled = compiler.compile(parsed: parsed, rawLines: lines);
      final context = interceptor.normalize(
        url: Uri.parse('https://ads.target.com/banner.js'),
        resourceType: 'script',
        frameUrl: Uri.parse('https://example.com/watch?v=1'),
        topLevelUrl: Uri.parse('https://example.com/watch?v=1'),
      );

      final decision = matcher.match(context, compiled);

      expect(decision.blocked, isFalse);
      expect(decision.reason, 'exception_rule');
      expect(decision.exceptionRule, isNotEmpty);
    });

    test('candidate narrowing avoids full scan for sparse token match', () {
      final lines = <String>[];
      for (var index = 0; index < 300; index += 1) {
        lines.add('||tracker$index.example.com^');
      }
      lines.add(r'||ads.target.com/banner.js$script');
      final parsed = parser.parse(lines);
      final compiled = compiler.compile(parsed: parsed, rawLines: lines);
      final context = interceptor.normalize(
        url: Uri.parse('https://ads.target.com/banner.js?slot=preroll'),
        resourceType: 'script',
        frameUrl: Uri.parse('https://news.example.com/article'),
        topLevelUrl: Uri.parse('https://news.example.com/article'),
      );

      final decision = matcher.match(context, compiled);

      expect(decision.blocked, isTrue);
      expect(decision.reason, 'compiled_network_rule');
      expect(decision.candidateCount, lessThan(compiled.networkRules.length));
      expect(decision.evaluatedCount, lessThan(compiled.networkRules.length));
    });

    test('split candidate API and match API return equivalent decision', () {
      const lines = <String>[
        r'||ads.target.com/banner.js$script',
        r'@@||ads.target.com/banner.js$domain=example.com',
      ];
      final parsed = parser.parse(lines);
      final compiled = compiler.compile(parsed: parsed, rawLines: lines);
      final context = interceptor.normalize(
        url: Uri.parse('https://ads.target.com/banner.js?slot=1'),
        resourceType: 'script',
        frameUrl: Uri.parse('https://example.com/watch?v=1'),
        topLevelUrl: Uri.parse('https://example.com/watch?v=1'),
      );

      final candidates = matcher.findCandidates(context, compiled);
      final splitDecision = matcher.evaluateCandidates(
        context,
        compiled,
        candidates,
      );
      final directDecision = matcher.match(context, compiled);

      expect(candidates.candidateCount, greaterThan(0));
      expect(splitDecision.blocked, directDecision.blocked);
      expect(splitDecision.reason, directDecision.reason);
      expect(splitDecision.exceptionRule, directDecision.exceptionRule);
    });

    test('regex candidates stay narrowed when index already matched', () {
      final lines = <String>[];
      for (var index = 0; index < 200; index += 1) {
        lines.add('/tracker$index\\.example\\.com\\/pixel/' r'$image');
      }
      lines.add('/ads\\.target\\.com\\/banner\\.js/' r'$script');
      final parsed = parser.parse(lines);
      final compiled = compiler.compile(parsed: parsed, rawLines: lines);
      final context = interceptor.normalize(
        url: Uri.parse('https://ads.target.com/banner.js?slot=1'),
        resourceType: 'script',
        frameUrl: Uri.parse('https://news.example.com/article'),
        topLevelUrl: Uri.parse('https://news.example.com/article'),
      );

      final candidates = matcher.findCandidates(context, compiled);
      final decision = matcher.evaluateCandidates(context, compiled, candidates);

      expect(decision.blocked, isTrue);
      expect(candidates.candidateCount, lessThan(compiled.networkRules.length));
      expect(decision.evaluatedCount, lessThan(compiled.networkRules.length));
    });

    test('regex exception overrides non-regex block when applicable', () {
      const lines = <String>[
        r'||ads.target.com/banner.js$script',
        r'@@/ads\.target\.com\/banner\.js/$script,domain=example.com',
      ];
      final parsed = parser.parse(lines);
      final compiled = compiler.compile(parsed: parsed, rawLines: lines);
      final context = interceptor.normalize(
        url: Uri.parse('https://ads.target.com/banner.js'),
        resourceType: 'script',
        frameUrl: Uri.parse('https://example.com/watch?v=1'),
        topLevelUrl: Uri.parse('https://example.com/watch?v=1'),
      );

      final candidates = matcher.findCandidates(context, compiled);
      final decision = matcher.evaluateCandidates(
        context,
        compiled,
        candidates,
      );

      expect(decision.blocked, isFalse);
      expect(decision.reason, 'exception_rule_regex');
    });

    test('returns redirect decision from compiled network rules', () {
      const lines = <String>[
        r'||ads.target.com/banner.js$script,redirect=noopjs',
      ];
      final parsed = parser.parse(lines);
      final compiled = compiler.compile(parsed: parsed, rawLines: lines);
      final context = interceptor.normalize(
        url: Uri.parse('https://ads.target.com/banner.js'),
        resourceType: 'script',
        frameUrl: Uri.parse('https://news.example.com/article'),
        topLevelUrl: Uri.parse('https://news.example.com/article'),
      );

      final decision = matcher.match(context, compiled);

      expect(decision.blocked, isTrue);
      expect(decision.reason, 'compiled_network_redirect_rule');
      expect(decision.redirectDataUrl, startsWith('data:'));
    });

    test('returns rewrite decision from compiled network rules', () {
      const lines = <String>[
        r'||api.target.com/v1/ad$xmlhttprequest,rewrite=https://example.com/blank',
      ];
      final parsed = parser.parse(lines);
      final compiled = compiler.compile(parsed: parsed, rawLines: lines);
      final context = interceptor.normalize(
        url: Uri.parse('https://api.target.com/v1/ad'),
        resourceType: 'xmlhttprequest',
        frameUrl: Uri.parse('https://news.example.com/article'),
        topLevelUrl: Uri.parse('https://news.example.com/article'),
      );

      final decision = matcher.match(context, compiled);

      expect(decision.blocked, isFalse);
      expect(decision.reason, 'compiled_network_rewrite_rule');
      expect(decision.rewrittenUrl, 'https://example.com/blank');
    });

    test('enforces third-party option with normalized context', () {
      const lines = <String>[r'||cdn.target.com/ad.js$script,third-party'];
      final parsed = parser.parse(lines);
      final compiled = compiler.compile(parsed: parsed, rawLines: lines);

      final firstParty = interceptor.normalize(
        url: Uri.parse('https://cdn.target.com/ad.js'),
        resourceType: 'script',
        frameUrl: Uri.parse('https://news.target.com/watch'),
        topLevelUrl: Uri.parse('https://news.target.com/watch'),
      );
      final thirdParty = interceptor.normalize(
        url: Uri.parse('https://cdn.target.com/ad.js'),
        resourceType: 'script',
        frameUrl: Uri.parse('https://news.example.com/article'),
        topLevelUrl: Uri.parse('https://news.example.com/article'),
      );

      final firstPartyDecision = matcher.match(firstParty, compiled);
      final thirdPartyDecision = matcher.match(thirdParty, compiled);

      expect(firstPartyDecision.blocked, isFalse);
      expect(thirdPartyDecision.blocked, isTrue);
    });

    test('enforces resource-type option', () {
      const lines = <String>[r'||ads.target.com/creative$script'];
      final parsed = parser.parse(lines);
      final compiled = compiler.compile(parsed: parsed, rawLines: lines);
      final scriptContext = interceptor.normalize(
        url: Uri.parse('https://ads.target.com/creative'),
        resourceType: 'script',
        frameUrl: Uri.parse('https://news.example.com/article'),
        topLevelUrl: Uri.parse('https://news.example.com/article'),
      );
      final imageContext = interceptor.normalize(
        url: Uri.parse('https://ads.target.com/creative'),
        resourceType: 'image',
        frameUrl: Uri.parse('https://news.example.com/article'),
        topLevelUrl: Uri.parse('https://news.example.com/article'),
      );

      final scriptDecision = matcher.match(scriptContext, compiled);
      final imageDecision = matcher.match(imageContext, compiled);

      expect(scriptDecision.blocked, isTrue);
      expect(imageDecision.blocked, isFalse);
    });

    test('marks regex fallback when only regex rules match candidate path', () {
      const lines = <String>[r'/ads\.target\.com\/banner\.js/$script'];
      final parsed = parser.parse(lines);
      final compiled = compiler.compile(parsed: parsed, rawLines: lines);
      final context = interceptor.normalize(
        url: Uri.parse('https://ads.target.com/banner.js'),
        resourceType: 'script',
        frameUrl: Uri.parse('https://news.example.com/article'),
        topLevelUrl: Uri.parse('https://news.example.com/article'),
      );

      final decision = matcher.match(context, compiled);

      expect(decision.blocked, isTrue);
      expect(decision.reason, 'compiled_network_rule_regex');
      expect(decision.usedRegexFallback, isTrue);
    });
  });
}
