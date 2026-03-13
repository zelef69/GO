import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/adblock/adblock_engine_bridge.dart';
import 'package:go_play/features/adblock/config/filter_source_manager.dart';
import 'package:go_play/features/adblock/core/adblock_config.dart';
import 'package:go_play/features/adblock/core/adblock_debug_logger.dart';
import 'package:go_play/features/adblock/core/adblock_engine.dart';
import 'package:go_play/features/adblock/core/adblock_metrics.dart';
import 'package:go_play/features/adblock/core/engine_adapter.dart';
import 'package:go_play/features/adblock/core/filter_list_repository.dart';
import 'package:go_play/features/adblock/core/request_runtime_models.dart';
import 'package:go_play/features/adblock/core/types.dart';
import 'package:go_play/features/adblock/filters/filter_compiler.dart';
import 'package:go_play/features/adblock/filters/filter_parser.dart';
import 'package:go_play/features/adblock/injection/scriptlet_engine.dart';
import 'package:go_play/features/adblock/intercept/request_interceptor.dart';
import 'package:go_play/features/adblock/matchers/cosmetic_matcher.dart';
import 'package:go_play/features/adblock/matchers/request_matcher.dart';
import 'package:go_play/features/adblock/models/adblock_rule.dart';
import 'package:go_play/features/domain_lock/domain_policy_service.dart';

void main() {
  group('AdblockEngine', () {
    test('caches repeated request decisions and reports cache stats', () async {
      final engine = await _buildEngine(const <String>[
        r'||ads.target.com/banner.js$script',
      ]);
      addTearDown(engine.dispose);
      const interceptor = RequestInterceptor();
      final context = interceptor.normalize(
        url: Uri.parse('https://ads.target.com/banner.js'),
        resourceType: 'script',
        frameUrl: Uri.parse('https://news.example.com/article'),
        topLevelUrl: Uri.parse('https://news.example.com/article'),
      );

      final first = await engine.evaluateRequest(context);
      final second = await engine.evaluateRequest(context);
      final stats = engine.getEngineStats();

      expect(first.action, DecisionAction.block);
      expect(second.action, DecisionAction.block);
      expect(second.fromCache, isTrue);
      expect(stats.totalRequestEvaluations, 2);
      expect(stats.decisionCacheMisses, 1);
      expect(stats.decisionCacheHits, 1);
      expect(stats.decisionCacheHitRate, closeTo(0.5, 0.001));
    });

    test('returns redirect action from local compiled matcher', () async {
      final engine = await _buildEngine(const <String>[
        r'||ads.target.com/banner.js$script,redirect=noopjs',
      ]);
      addTearDown(engine.dispose);
      const interceptor = RequestInterceptor();
      final context = interceptor.normalize(
        url: Uri.parse('https://ads.target.com/banner.js'),
        resourceType: 'script',
        frameUrl: Uri.parse('https://news.example.com/article'),
        topLevelUrl: Uri.parse('https://news.example.com/article'),
      );

      final decision = await engine.evaluateRequest(context);

      expect(decision.action, DecisionAction.redirect);
      expect(decision.redirectDataUrl, startsWith('data:'));
    });

    test('records normalization timing via runtime policy path', () async {
      final engine = await _buildEngine(const <String>[
        r'||ads.target.com/banner.js$script',
      ]);
      addTearDown(engine.dispose);

      await engine.evaluateAdblockRequest(
        AdblockRequestContext(
          uri: Uri.parse('https://m.youtube.com/api/test'),
          resourceType: 'xmlhttprequest',
          sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
          fromServiceWorker: false,
          adShowing: false,
        ),
      );
      final stats = engine.getEngineStats();

      expect(stats.lastNormalizationMicros, greaterThanOrEqualTo(0));
      expect(stats.totalRequestEvaluations, greaterThan(0));
      expect(stats.lastCandidateLookupMicros, greaterThanOrEqualTo(0));
      expect(stats.lastCandidateEvaluationMicros, greaterThanOrEqualTo(0));
    });
  });
}

Future<AdblockEngine> _buildEngine(List<String> lines) async {
  final config = AdblockConfig.defaults(enabled: true, debugMode: false);
  final logger = AdblockDebugLogger(enabled: false);
  final adapter = EngineAdapter(
    nativeEngineBridge: _UnavailableBridge(),
    fallbackEngineBridge: _UnavailableBridge(),
    logger: logger,
  );
  final engine = AdblockEngine(
    sourceManager: FilterSourceManager(
      repository: _FakeFilterListRepository(lines),
    ),
    parser: const FilterParser(),
    compiler: const IndexedFilterCompiler(),
    requestMatcher: const RequestMatcher(),
    cosmeticMatcher: const CosmeticMatcher(),
    scriptletEngine: const ScriptletEngine(),
    requestInterceptor: const RequestInterceptor(),
    bridge: adapter,
    logger: logger,
    domainPolicyService: DomainPolicyService(),
    metrics: AdblockMetricsCollector(),
    initialConfig: config,
  );
  await engine.initializeCore(config: config);
  return engine;
}

class _FakeFilterListRepository extends FilterListRepository {
  _FakeFilterListRepository(this._lines);

  final List<String> _lines;

  @override
  Future<FilterListBundle> loadLists({
    required AdblockConfig config,
    required AdblockDebugLogger logger,
  }) async {
    return FilterListBundle(
      lines: List<String>.unmodifiable(_lines),
      loadedSources: const <String>['test:list'],
      usedCachedData: false,
      rawFilterText: _lines.join('\n'),
      resourcesJson: '[]',
      enabledTags: const <String>[],
      catalogSourcesJson: '[]',
      firstPartyHeuristicsProfileEnabled: false,
    );
  }
}

class _UnavailableBridge implements AdblockEngineBridge {
  @override
  Future<void> dispose() async {}

  @override
  Future<AdblockEngineRequestResult> evaluateRequestDetailed(
    Uri uri, {
    required String resourceType,
    Uri? sourceUrl,
  }) async {
    return AdblockEngineRequestResult.allow();
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
  Future<void> initialize(
    List<AdblockRule> rules, {
    String? rawFilterText,
    String? resourcesJson,
    String? catalogSourcesJson,
    String? serializedEngineBase64,
    List<String> enabledTags = const <String>[],
  }) async {
    throw StateError('bridge unavailable');
  }

  @override
  Future<bool> isAvailable() async {
    return false;
  }

  @override
  Future<String?> serializeEngine() async {
    return null;
  }

  @override
  Future<bool> shouldBlock(
    Uri uri, {
    required String resourceType,
    Uri? sourceUrl,
  }) async {
    return false;
  }
}
