import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/adblock/adblock_engine_bridge.dart';
import 'package:go_play/features/adblock/core/adblock_config.dart';
import 'package:go_play/features/adblock/core/adblock_debug_logger.dart';
import 'package:go_play/features/adblock/core/adblock_metrics.dart';
import 'package:go_play/features/adblock/models/adblock_rule.dart';
import 'package:go_play/features/adblock/core/request_blocker.dart';
import 'package:go_play/features/domain_lock/domain_policy_service.dart';

void main() {
  group('RequestBlocker', () {
    late _FakeEngine engine;
    late RequestBlocker blocker;

    setUp(() {
      engine = _FakeEngine();
      blocker = RequestBlocker(
        domainPolicyService: DomainPolicyService(),
        logger: AdblockDebugLogger(enabled: false),
        metrics: AdblockMetricsCollector(),
      );
      blocker
        ..setConfig(AdblockConfig.defaults(enabled: true, debugMode: false))
        ..setEngine(engine);
    });

    test('returns disabled decision when feature is off', () async {
      blocker.setConfig(
        AdblockConfig.defaults(enabled: false, debugMode: false),
      );

      final decision = await blocker.evaluate(
        AdblockRequestContext(
          uri: Uri.parse('https://m.youtube.com/watch?v=abc'),
          resourceType: 'document',
          sourceUrl: Uri.parse('https://m.youtube.com/'),
          fromServiceWorker: false,
        ),
      );

      expect(decision.blocked, isFalse);
      expect(decision.reason, 'disabled');
    });

    test('respects host allowlist', () async {
      blocker.setConfig(
        AdblockConfig.defaults(
          enabled: true,
          debugMode: false,
        ).copyWith(allowlistedHosts: const <String>{'doubleclick.net'}),
      );

      final decision = await blocker.evaluate(
        AdblockRequestContext(
          uri: Uri.parse('https://pubads.g.doubleclick.net/gampad/ads'),
          resourceType: 'xmlhttprequest',
          sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
          fromServiceWorker: false,
        ),
      );

      expect(decision.blocked, isFalse);
      expect(decision.reason, 'allowlisted_host');
    });

    test('respects host blocklist', () async {
      blocker.setConfig(
        AdblockConfig.defaults(
          enabled: true,
          debugMode: false,
        ).copyWith(blocklistedHosts: const <String>{'m.youtube.com'}),
      );

      final decision = await blocker.evaluate(
        AdblockRequestContext(
          uri: Uri.parse('https://m.youtube.com/watch?v=abc'),
          resourceType: 'document',
          sourceUrl: Uri.parse('https://m.youtube.com/'),
          fromServiceWorker: false,
        ),
      );

      expect(decision.blocked, isTrue);
      expect(decision.reason, 'blocklisted_host');
    });

    test('uses heuristic matcher before engine', () async {
      final decision = await blocker.evaluate(
        AdblockRequestContext(
          uri: Uri.parse('https://m.youtube.com/api/stats/ads'),
          resourceType: 'xmlhttprequest',
          sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
          fromServiceWorker: false,
        ),
      );

      expect(decision.blocked, isTrue);
      expect(decision.reason, 'heuristic_matcher');
      expect(engine.callCount, 0);
    });

    test('uses media fast path for non-ad googlevideo playback', () async {
      final decision = await blocker.evaluate(
        AdblockRequestContext(
          uri: Uri.parse(
            'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&itag=18',
          ),
          resourceType: 'media',
          sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
          fromServiceWorker: false,
        ),
      );

      expect(decision.blocked, isFalse);
      expect(decision.reason, 'media_fast_path');
      expect(engine.callCount, 0);
    });

    test('blocks googlevideo playback with ad-like query key pattern', () async {
      final decision = await blocker.evaluate(
        AdblockRequestContext(
          uri: Uri.parse(
            'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&itag=18&ads_payload=1',
          ),
          resourceType: 'media',
          sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
          fromServiceWorker: false,
        ),
      );

      expect(decision.blocked, isTrue);
      expect(decision.reason, 'googlevideo_ad_query');
      expect(engine.callCount, 0);
    });

    test('blocks googlevideo playback when ctier marks ad traffic', () async {
      final decision = await blocker.evaluate(
        AdblockRequestContext(
          uri: Uri.parse(
            'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&itag=18&ctier=A2',
          ),
          resourceType: 'media',
          sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
          fromServiceWorker: false,
        ),
      );

      expect(decision.blocked, isTrue);
      expect(decision.reason, 'googlevideo_ad_query');
      expect(engine.callCount, 0);
    });

    test('memoizes recent decisions in cache', () async {
      final request = AdblockRequestContext(
        uri: Uri.parse('https://fonts.gstatic.com/by-engine-block.js'),
        resourceType: 'script',
        sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
        fromServiceWorker: false,
      );

      final first = await blocker.evaluate(request);
      final second = await blocker.evaluate(request);

      expect(first.blocked, isTrue);
      expect(second.blocked, isTrue);
      expect(second.fromCache, isTrue);
      expect(engine.callCount, 1);
    });

    test('passes through document requests after domain policy', () async {
      final decision = await blocker.evaluate(
        AdblockRequestContext(
          uri: Uri.parse('https://m.youtube.com/watch?v=abc'),
          resourceType: 'document',
          sourceUrl: Uri.parse('https://m.youtube.com/'),
          fromServiceWorker: false,
        ),
      );

      expect(decision.blocked, isFalse);
      expect(decision.reason, 'document_pass_through');
      expect(engine.callCount, 0);
    });
  });
}

class _FakeEngine implements AdblockEngineBridge {
  int callCount = 0;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize(List<AdblockRule> rules) async {}

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> shouldBlock(
    Uri uri, {
    required String resourceType,
    Uri? sourceUrl,
  }) async {
    callCount += 1;
    return uri.path.contains('by-engine-block');
  }
}
