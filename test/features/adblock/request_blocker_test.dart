import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/adblock/adblock_engine_bridge.dart';
import 'package:go_play/features/adblock/crowd/models/learned_signature.dart';
import 'package:go_play/features/adblock/crowd/signature/signature_matcher.dart';
import 'package:go_play/features/adblock/crowd/storage/learned_signature_db.dart';
import 'package:go_play/features/adblock/crowd/storage/learned_signature_repository.dart';
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
      expect(decision.reason, 'media_fast_path');
      expect(engine.callCount, 0);
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
      'does not block soft marker without ad signal even when ad is showing',
      () async {
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

        expect(decision.blocked, isFalse);
        expect(decision.reason, 'media_fast_path');
        expect(engine.callCount, 0);
      },
    );

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
      expect(decision.reason, 'googlevideo_ad_query_soft');
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
      expect(decision.reason, 'googlevideo_ad_query_soft');
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
        expect(decision.reason, 'googlevideo_ad_query_soft');
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
        expect(decision.reason, 'media_fast_path');
        expect(engine.callCount, 0);
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
          expect(blocked.reason, 'googlevideo_ad_query_soft');
        }

        final bypassed = await blocker.evaluate(request);
        expect(bypassed.blocked, isFalse);
        expect(bypassed.reason, 'media_fast_path');
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
      expect(decision.reason, 'playback_stall_backoff');
      expect(engine.callCount, 0);
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

class _FakeEngine implements AdblockEngineBridge {
  int callCount = 0;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize(
    List<AdblockRule> rules, {
    String? rawFilterText,
    String? resourcesJson,
    String? catalogSourcesJson,
    String? serializedEngineBase64,
    List<String> enabledTags = const <String>[],
  }) async {}

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> shouldBlock(
    Uri uri, {
    required String resourceType,
    Uri? sourceUrl,
  }) async {
    final result = await evaluateRequestDetailed(
      uri,
      resourceType: resourceType,
      sourceUrl: sourceUrl,
    );
    return result.blocked;
  }

  @override
  Future<AdblockEngineRequestResult> evaluateRequestDetailed(
    Uri uri, {
    required String resourceType,
    Uri? sourceUrl,
  }) async {
    callCount += 1;
    if (uri.path.contains('by-engine-block')) {
      return const AdblockEngineRequestResult(
        blocked: true,
        matched: true,
        redirectDataUrl: null,
        rewrittenUrl: null,
        important: false,
        exceptionRule: null,
        matchedRule: null,
      );
    }
    return AdblockEngineRequestResult.allow();
  }

  @override
  Future<AdblockCosmeticResources?> getCosmeticResources(Uri pageUri) async {
    return null;
  }

  @override
  Future<List<String>> getHiddenClassIdSelectors(
    Uri pageUri, {
    required List<String> classes,
    required List<String> ids,
    Set<String> exceptions = const <String>{},
  }) async {
    return const <String>[];
  }

  @override
  Future<String?> getCspDirectives(
    Uri uri, {
    required String resourceType,
    Uri? sourceUrl,
  }) async {
    return null;
  }

  @override
  Future<String?> serializeEngine() async {
    return null;
  }
}
