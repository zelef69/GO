import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/adblock/crowd/models/learned_signature.dart';
import 'package:go_play/features/adblock/crowd/signature/signature_matcher.dart';
import 'package:go_play/features/adblock/crowd/storage/learned_signature_db.dart';
import 'package:go_play/features/adblock/crowd/storage/learned_signature_repository.dart';
import 'package:go_play/features/adblock/core/adblock_config.dart';
import 'package:go_play/features/adblock/core/adblock_debug_logger.dart';
import 'package:go_play/features/adblock/core/adblock_metrics.dart';
import 'package:go_play/features/adblock/core/adblock_request_runtime_engine.dart';
import 'package:go_play/features/adblock/core/request_blocker.dart';
import 'package:go_play/features/adblock/core/types.dart';
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
        ..setFirstPartyHeuristicProfile(true)
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
          adShowing: false,
        ),
      );

      expect(decision.blocked, isFalse);
      expect(decision.reason, 'disabled');
    });

    test(
      'delegates runtime decision to AdblockRequestRuntimeEngine when available',
      () async {
        final runtimeEngine = _FakeRuntimeEngine();
        blocker.setEngine(runtimeEngine);

        final decision = await blocker.evaluate(
          AdblockRequestContext(
            uri: Uri.parse('https://example.com/asset.js'),
            resourceType: 'script',
            sourceUrl: Uri.parse('https://example.com/'),
            fromServiceWorker: false,
            adShowing: false,
          ),
        );

        expect(runtimeEngine.evaluateCount, 1);
        expect(decision.blocked, isTrue);
        expect(decision.reason, 'runtime_engine');
      },
    );

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
          adShowing: false,
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
          adShowing: false,
        ),
      );

      expect(decision.blocked, isTrue);
      expect(decision.reason, 'blocklisted_host');
    });

    test('uses heuristic matcher before engine', () async {
      final decision = await blocker.evaluate(
        AdblockRequestContext(
          uri: Uri.parse('https://m.youtube.com/youtubei/v1/player/ad_break'),
          resourceType: 'xmlhttprequest',
          sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
          fromServiceWorker: false,
          adShowing: false,
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
            'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&itag=18&expire=1773330000',
          ),
          resourceType: 'media',
          sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
          fromServiceWorker: false,
          adShowing: false,
        ),
      );

      expect(decision.blocked, isFalse);
      expect(decision.reason, anyOf('media_fast_path', 'allowed'));
      expect(engine.callCount, inInclusiveRange(0, 1));
    });

    test(
      'routes non-media googlevideo playback through engine instead of fast path',
      () async {
        final decision = await blocker.evaluate(
          AdblockRequestContext(
            uri: Uri.parse(
              'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&itag=18&expire=1773330000',
            ),
            resourceType: 'other',
            sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
            fromServiceWorker: false,
            adShowing: false,
          ),
        );

        expect(decision.blocked, isFalse);
        expect(decision.reason, 'allowed');
        expect(engine.callCount, 1);
      },
    );

    test('blocks googlevideo playback with ad-like query key pattern', () async {
      final decision = await blocker.evaluate(
        AdblockRequestContext(
          uri: Uri.parse(
            'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&itag=18&ads_payload=1',
          ),
          resourceType: 'media',
          sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
          fromServiceWorker: false,
          adShowing: false,
        ),
      );

      expect(decision.blocked, isTrue);
      expect(decision.reason, 'googlevideo_ad_query_hard');
      expect(engine.callCount, 0);
    });

    test('blocks googlevideo playback when ad telemetry key appears', () async {
      final decision = await blocker.evaluate(
        AdblockRequestContext(
          uri: Uri.parse(
            'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&itag=18&ad_mt=17',
          ),
          resourceType: 'media',
          sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
          fromServiceWorker: false,
          adShowing: false,
        ),
      );

      expect(decision.blocked, isTrue);
      expect(decision.reason, 'googlevideo_ad_query_hard');
      expect(engine.callCount, 0);
    });

    test('blocks googlevideo playback when ad telemetry label appears', () async {
      final decision = await blocker.evaluate(
        AdblockRequestContext(
          uri: Uri.parse(
            'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&itag=18&label=admute',
          ),
          resourceType: 'media',
          sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
          fromServiceWorker: false,
          adShowing: false,
        ),
      );

      expect(decision.blocked, isTrue);
      expect(decision.reason, 'googlevideo_ad_query_hard');
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
          adShowing: false,
        ),
      );

      expect(decision.blocked, isTrue);
      expect(decision.reason, 'googlevideo_ad_query_hard');
      expect(engine.callCount, 0);
    });

    test(
      'blocks youtube pagead interaction with ad markers during watch/ad state',
      () async {
        final decision = await blocker.evaluate(
          AdblockRequestContext(
            uri: Uri.parse(
              'https://www.youtube.com/pagead/interaction/?label=videoplaytime75&ad_mt=4615',
            ),
            resourceType: 'xmlhttprequest',
            sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
            fromServiceWorker: false,
            adShowing: true,
          ),
        );

        expect(decision.blocked, isTrue);
        expect(decision.reason, 'pagead_interaction_guard');
        expect(engine.callCount, 0);
      },
    );

    test(
      'keeps non-ad youtube pagead interaction on telemetry fast path',
      () async {
        final decision = await blocker.evaluate(
          AdblockRequestContext(
            uri: Uri.parse(
              'https://www.youtube.com/pagead/interaction/?foo=bar',
            ),
            resourceType: 'xmlhttprequest',
            sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
            fromServiceWorker: false,
            adShowing: false,
          ),
        );

        expect(decision.blocked, isFalse);
        expect(decision.reason, 'youtube_telemetry_fast_path');
        expect(engine.callCount, 0);
      },
    );

    test(
      'blocks pagead interaction with strong ad markers without adShowing signal',
      () async {
        final decision = await blocker.evaluate(
          AdblockRequestContext(
            uri: Uri.parse(
              'https://www.youtube.com/pagead/interaction/?label=videoplaytime50&ad_mt=7649&acvw=sv%3D968&dur=15000',
            ),
            resourceType: 'xmlhttprequest',
            sourceUrl: Uri.parse(
              'https://m.youtube.com/results?search_query=x',
            ),
            fromServiceWorker: false,
            adShowing: false,
          ),
        );

        expect(decision.blocked, isTrue);
        expect(decision.reason, 'pagead_interaction_guard');
        expect(engine.callCount, 0);
      },
    );

    test('blocks aggressive soft marker while ad is showing', () async {
      final decision = await blocker.evaluate(
        AdblockRequestContext(
          uri: Uri.parse(
            'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&itag=18&expire=1773330000&label=adbreak',
          ),
          resourceType: 'media',
          sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
          fromServiceWorker: false,
          adShowing: true,
        ),
      );

      expect(decision.blocked, isTrue);
        expect(
          decision.reason,
          anyOf('googlevideo_ad_query_soft', 'googlevideo_ad_showing_strict'),
        );
      expect(engine.callCount, 0);
    });

    test('blocks conservative soft marker while ad is showing', () async {
      final decision = await blocker.evaluate(
        AdblockRequestContext(
          uri: Uri.parse(
            'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&itag=18&expire=1773330000&ad_break_id=pod01',
          ),
          resourceType: 'media',
          sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
          fromServiceWorker: false,
          adShowing: true,
        ),
      );

      expect(decision.blocked, isTrue);
        expect(
          decision.reason,
          anyOf('googlevideo_ad_query_soft', 'googlevideo_ad_showing_strict'),
        );
      expect(engine.callCount, 0);
    });

    test('uses guarded aggressive block after ad signal is detected', () async {
      final seedSignal = await blocker.evaluate(
        AdblockRequestContext(
          uri: Uri.parse(
            'https://www.youtube.com/pagead/interaction/?label=videoplaytime75&ad_mt=4615',
          ),
          resourceType: 'xmlhttprequest',
          sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
          fromServiceWorker: false,
          adShowing: true,
        ),
      );
      expect(seedSignal.blocked, isTrue);
      expect(seedSignal.reason, 'pagead_interaction_guard');

      final decision = await blocker.evaluate(
        AdblockRequestContext(
          uri: Uri.parse(
            'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&itag=18&expire=1773330000&label=adbreak',
          ),
          resourceType: 'media',
          sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
          fromServiceWorker: false,
          adShowing: true,
        ),
      );

      expect(decision.blocked, isTrue);
      expect(
        decision.reason,
        anyOf('googlevideo_ad_query_soft', 'googlevideo_ad_showing_strict'),
      );
      expect(engine.callCount, 0);
    });

    test(
      'blocks leaked googlevideo ad query pattern while ad is showing',
      () async {
        final seedSignal = await blocker.evaluate(
          AdblockRequestContext(
            uri: Uri.parse(
              'https://www.youtube.com/pagead/interaction/?label=videoplaytime75&ad_mt=4615',
            ),
            resourceType: 'xmlhttprequest',
            sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
            fromServiceWorker: false,
            adShowing: true,
          ),
        );
        expect(seedSignal.blocked, isTrue);
        expect(seedSignal.reason, 'pagead_interaction_guard');

        final decision = await blocker.evaluate(
          AdblockRequestContext(
            uri: Uri.parse(
              'https://rr2---sn-abc.googlevideo.com/videoplayback?expire=1773361426&id=o-abc&source=youtube&svpuc=1&sabr=1&rqh=1&c=MWEB&sparams=expire%2Cid%2Csource%2Csvpuc%2Csabr%2Crqh',
            ),
            resourceType: 'media',
            sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
            fromServiceWorker: false,
            adShowing: true,
          ),
        );

        expect(decision.blocked, isTrue);
        expect(
          decision.reason,
          anyOf(
            'googlevideo_ad_query_soft_leaked',
            'googlevideo_ad_showing_strict',
          ),
        );
        expect(engine.callCount, 0);
      },
    );

    test(
      'blocks leaked googlevideo ad query pattern while ad is showing and stalled',
      () async {
        final seedSignal = await blocker.evaluate(
          AdblockRequestContext(
            uri: Uri.parse(
              'https://www.youtube.com/pagead/interaction/?label=videoplaytime75&ad_mt=4615',
            ),
            resourceType: 'xmlhttprequest',
            sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
            fromServiceWorker: false,
            adShowing: true,
          ),
        );
        expect(seedSignal.blocked, isTrue);
        expect(seedSignal.reason, 'pagead_interaction_guard');

        final decision = await blocker.evaluate(
          AdblockRequestContext(
            uri: Uri.parse(
              'https://rr2---sn-abc.googlevideo.com/videoplayback?expire=1773361426&id=o-abc&source=youtube&svpuc=1&sabr=1&rqh=1&c=MWEB&sparams=expire%2Cid%2Csource%2Csvpuc%2Csabr%2Crqh',
            ),
            resourceType: 'media',
            sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
            fromServiceWorker: false,
            adShowing: true,
            playbackStalled: true,
          ),
        );

        expect(decision.blocked, isTrue);
        expect(decision.reason, 'googlevideo_ad_query_soft_leaked');
        expect(engine.callCount, 0);
      },
    );

    test(
      'does not use guarded aggressive block while ad is not showing',
      () async {
        final decision = await blocker.evaluate(
          AdblockRequestContext(
            uri: Uri.parse(
              'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&itag=18&expire=1773330000&label=adbreak',
            ),
            resourceType: 'media',
            sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
            fromServiceWorker: false,
            adShowing: false,
          ),
        );

        expect(decision.blocked, isFalse);
        expect(decision.reason, anyOf('media_fast_path', 'allowed'));
        expect(engine.callCount, inInclusiveRange(0, 1));
      },
    );

    test(
      'temporarily bypasses soft ad-showing guard after repeated burst blocks',
      () async {
        final seedSignal = await blocker.evaluate(
          AdblockRequestContext(
            uri: Uri.parse(
              'https://www.youtube.com/pagead/interaction/?label=videoplaytime75&ad_mt=4615',
            ),
            resourceType: 'xmlhttprequest',
            sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
            fromServiceWorker: false,
            adShowing: true,
          ),
        );
        expect(seedSignal.blocked, isTrue);
        expect(seedSignal.reason, 'pagead_interaction_guard');

        final request = AdblockRequestContext(
          uri: Uri.parse(
            'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&itag=18&expire=1773330000&label=adbreak',
          ),
          resourceType: 'media',
          sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
          fromServiceWorker: false,
          adShowing: true,
        );

        for (var index = 0; index < 6; index += 1) {
          final blocked = await blocker.evaluate(request);
          expect(blocked.blocked, isTrue);
            expect(
              blocked.reason,
              anyOf('googlevideo_ad_query_soft', 'googlevideo_ad_showing_strict'),
            );
        }

        final bypassed = await blocker.evaluate(request);
        expect(bypassed.blocked, isTrue);
        expect(
          bypassed.reason,
          anyOf(
            'googlevideo_ad_query_soft',
            'googlevideo_ad_window_escalation',
            'googlevideo_ad_showing_strict',
          ),
        );
      },
    );

    test(
      'escalates repeated no-marker googlevideo allows during ad window',
      () async {
        final request = AdblockRequestContext(
          uri: Uri.parse(
            'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&expire=1773330000&source=youtube',
          ),
          resourceType: 'xmlhttprequest',
          sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
          fromServiceWorker: false,
          adShowing: true,
        );

        final first = await blocker.evaluate(request);
        final second = await blocker.evaluate(request);
        final observedBlocked = first.blocked || second.blocked;

        expect(observedBlocked, isTrue);
        if (first.blocked) {
          expect(
            first.reason,
            anyOf('googlevideo_ad_window_escalation', 'googlevideo_ad_showing_strict'),
          );
        }
        if (second.blocked) {
          expect(
            second.reason,
            anyOf('googlevideo_ad_window_escalation', 'googlevideo_ad_showing_strict'),
          );
        }
      },
    );

    test(
      'escalates repeated no-marker googlevideo media allows during ad window',
      () async {
        final request = AdblockRequestContext(
          uri: Uri.parse(
            'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&expire=1773330000&source=youtube',
          ),
          resourceType: 'media',
          sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
          fromServiceWorker: false,
          adShowing: true,
        );

        final first = await blocker.evaluate(request);
        final second = await blocker.evaluate(request);
        final observedBlocked = first.blocked || second.blocked;

        expect(observedBlocked, isTrue);
        if (first.blocked) {
          expect(
            first.reason,
            anyOf('googlevideo_ad_window_escalation', 'googlevideo_ad_showing_strict'),
          );
        }
        if (second.blocked) {
          expect(
            second.reason,
            anyOf('googlevideo_ad_window_escalation', 'googlevideo_ad_showing_strict'),
          );
        }
      },
    );

    test(
      'does not cache allow decisions for ad-showing googlevideo requests',
      () async {
        final request = AdblockRequestContext(
          uri: Uri.parse(
            'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&expire=1773330000&source=youtube',
          ),
          resourceType: 'media',
          sourceUrl: Uri.parse('https://m.youtube.com/'),
          fromServiceWorker: false,
          adShowing: true,
        );

        final first = await blocker.evaluate(request);
        final second = await blocker.evaluate(request);

        expect(first.blocked, isFalse);
        expect(first.reason, 'allowed');
        expect(second.blocked, isFalse);
        expect(second.reason, 'allowed');
        expect(engine.callCount, 2);
      },
    );

    test(
      'applies post-burst recovery backoff to avoid ad-transition stalls',
      () async {
        final burstRequest = AdblockRequestContext(
          uri: Uri.parse(
            'https://www.youtube.com/pagead/interaction/?label=videoplaytime75&ad_mt=4615',
          ),
          resourceType: 'xmlhttprequest',
          sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
          fromServiceWorker: false,
          adShowing: true,
        );

        for (var index = 0; index < 12; index += 1) {
          final blocked = await blocker.evaluate(burstRequest);
          expect(blocked.blocked, isTrue);
        }

        final recoveryCandidate = await blocker.evaluate(
          AdblockRequestContext(
            uri: Uri.parse(
              'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&expire=1773330000&ad_break_id=pod01',
            ),
            resourceType: 'xmlhttprequest',
            sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
            fromServiceWorker: false,
            adShowing: true,
          ),
        );

        expect(recoveryCandidate.blocked, isTrue);
        expect(recoveryCandidate.reason.startsWith('googlevideo_'), isTrue);
        expect(engine.callCount, 0);
      },
    );

    test('keeps youtube log_event endpoint on telemetry fast path', () async {
      final decision = await blocker.evaluate(
        AdblockRequestContext(
          uri: Uri.parse('https://m.youtube.com/youtubei/v1/log_event?x=1'),
          resourceType: 'xmlhttprequest',
          sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
          fromServiceWorker: false,
          adShowing: false,
        ),
      );

      expect(decision.blocked, isFalse);
      expect(decision.reason, 'youtube_telemetry_fast_path');
      expect(engine.callCount, 0);
    });

    test(
      'routes youtube log_event through engine when first-party profile is disabled',
      () async {
        blocker.setFirstPartyHeuristicProfile(false);

        final decision = await blocker.evaluate(
          AdblockRequestContext(
            uri: Uri.parse('https://m.youtube.com/youtubei/v1/log_event?x=1'),
            resourceType: 'xmlhttprequest',
            sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
            fromServiceWorker: false,
            adShowing: false,
          ),
        );

        expect(decision.blocked, isFalse);
        expect(decision.reason, 'allowed');
        expect(engine.callCount, 1);
      },
    );

    test('keeps api stats atr endpoint on telemetry fast path', () async {
      final decision = await blocker.evaluate(
        AdblockRequestContext(
          uri: Uri.parse('https://m.youtube.com/api/stats/atr?x=1'),
          resourceType: 'xmlhttprequest',
          sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
          fromServiceWorker: false,
          adShowing: false,
        ),
      );

      expect(decision.blocked, isFalse);
      expect(decision.reason, 'youtube_telemetry_fast_path');
      expect(engine.callCount, 0);
    });

    test(
      'blocks googlevideo browse-surface xhr prefetch before watch page',
      () async {
        final decision = await blocker.evaluate(
          AdblockRequestContext(
            uri: Uri.parse(
              'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&expire=1773330000',
            ),
            resourceType: 'xmlhttprequest',
            sourceUrl: Uri.parse(
              'https://m.youtube.com/results?search_query=test',
            ),
            fromServiceWorker: false,
            adShowing: false,
          ),
        );

        expect(decision.blocked, isTrue);
        expect(decision.reason, 'googlevideo_browse_prefetch_guard');
        expect(engine.callCount, 0);
      },
    );

    test(
      'does not treat youtube root as browse surface for googlevideo playback',
      () async {
        final decision = await blocker.evaluate(
          AdblockRequestContext(
            uri: Uri.parse(
              'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&expire=1773330000',
            ),
            resourceType: 'xmlhttprequest',
            sourceUrl: Uri.parse('https://m.youtube.com/'),
            fromServiceWorker: false,
            adShowing: false,
          ),
        );

        expect(decision.blocked, isFalse);
        expect(decision.reason, 'allowed');
        expect(engine.callCount, 1);
      },
    );

    test('bypasses soft guard while playback is stalled', () async {
      final seedSignal = await blocker.evaluate(
        AdblockRequestContext(
          uri: Uri.parse(
            'https://www.youtube.com/pagead/interaction/?label=videoplaytime75&ad_mt=4615',
          ),
          resourceType: 'xmlhttprequest',
          sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
          fromServiceWorker: false,
          adShowing: true,
        ),
      );
      expect(seedSignal.blocked, isTrue);

      final decision = await blocker.evaluate(
        AdblockRequestContext(
          uri: Uri.parse(
            'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&itag=18&expire=1773330000&label=adbreak',
          ),
          resourceType: 'media',
          sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
          fromServiceWorker: false,
          adShowing: true,
          playbackStalled: true,
        ),
      );

      expect(decision.blocked, isFalse);
      expect(decision.reason, anyOf('media_fast_path', 'allowed'));
      expect(engine.callCount, inInclusiveRange(0, 1));
    });

    test('memoizes recent decisions in cache', () async {
      final request = AdblockRequestContext(
        uri: Uri.parse('https://fonts.gstatic.com/by-engine-block.js'),
        resourceType: 'script',
        sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
        fromServiceWorker: false,
        adShowing: false,
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
          adShowing: false,
        ),
      );

      expect(decision.blocked, isFalse);
      expect(decision.reason, 'document_pass_through');
      expect(engine.callCount, 0);
    });

    test('uses learned signature precheck before engine', () async {
      final fixedNow = DateTime.fromMillisecondsSinceEpoch(
        1730000000000,
        isUtc: true,
      );
      final repository = LearnedSignatureRepository(
        database: LearnedSignatureDb(),
        matcher: const SignatureMatcher(),
        now: () => fixedNow,
      );
      await repository.initialize();
      addTearDown(repository.dispose);
      await repository.applySnapshot(
        version: 1,
        checksum: 'checksum-v1',
        signatures: <LearnedSignature>[
          LearnedSignature(
            sigHash:
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            hostPattern: '*.googlevideo.com',
            pathPattern: '/videoplayback',
            resourceType: 'media',
            sourceHost: '*.youtube.com',
            markerKeys: const <String>['ad_break_id'],
            requireAdSignal: true,
            state: LearnedSignatureState.active,
            source: LearnedSignatureSource.cloud,
            score: 90,
            confidence: 0.92,
            seenCount: 12,
            falsePositiveCount: 0,
            firstSeenAtMs: fixedNow.millisecondsSinceEpoch - 120000,
            lastSeenAtMs: fixedNow.millisecondsSinceEpoch - 4000,
            expireAtMs:
                fixedNow.millisecondsSinceEpoch +
                const Duration(days: 15).inMilliseconds,
            updatedAtMs: fixedNow.millisecondsSinceEpoch - 1000,
            lastReason: 'seed_snapshot',
          ),
        ],
      );

      final learnedBlocker = RequestBlocker(
        domainPolicyService: DomainPolicyService(),
        logger: AdblockDebugLogger(enabled: false),
        metrics: AdblockMetricsCollector(),
        learnedSignatureRepository: repository,
      );
      learnedBlocker
        ..setConfig(AdblockConfig.defaults(enabled: true, debugMode: false))
        ..setFirstPartyHeuristicProfile(true)
        ..setEngine(engine);

      final decision = await learnedBlocker.evaluate(
        AdblockRequestContext(
          uri: Uri.parse(
            'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&itag=18&ad_break_id=pod01',
          ),
          resourceType: 'media',
          sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
          fromServiceWorker: false,
          adShowing: true,
        ),
      );

      expect(decision.blocked, isTrue);
      expect(decision.reason, 'learned_signature');
      expect(decision.matchedRule, isNotEmpty);
      expect(engine.callCount, 0);
    });
  });
}

class _FakeEngine implements AdblockRuntimeEngine {
  int callCount = 0;

  @override
  Future<RequestDecision> evaluateRequest(RequestContext context) async {
    callCount += 1;
    if (context.url.path.contains('by-engine-block')) {
      return RequestDecision.block(reason: 'engine_match', matchedRule: 'fake');
    }
    return RequestDecision.allow(reason: 'engine_allow');
  }

  @override
  Future<CosmeticPayload> getCosmeticPayload(PageContext pageContext) async {
    return CosmeticPayload.empty();
  }

  @override
  Future<ScriptletPayload> getScriptletPayload(PageContext pageContext) async {
    return ScriptletPayload.empty();
  }
}

class _FakeRuntimeEngine implements AdblockRequestRuntimeEngine {
  int evaluateCount = 0;

  @override
  Future<AdblockDecision> evaluateAdblockRequest(
    AdblockRequestContext request,
  ) async {
    evaluateCount += 1;
    return const AdblockDecision(blocked: true, reason: 'runtime_engine');
  }

  @override
  void clearRuntimeCache() {}

  @override
  Future<CosmeticPayload> getCosmeticPayload(PageContext pageContext) async {
    return CosmeticPayload.empty();
  }

  @override
  Future<ScriptletPayload> getScriptletPayload(PageContext pageContext) async {
    return ScriptletPayload.empty();
  }

  @override
  void onPlaybackDebugSignal(Map<String, dynamic> payload, {Uri? pageUri}) {}

  @override
  Future<RequestDecision> evaluateRequest(RequestContext context) async {
    return RequestDecision.allow();
  }

  @override
  void setFirstPartyHeuristicProfile(bool enabled) {}

  @override
  void setRuntimeConfig(AdblockConfig config) {}
}
