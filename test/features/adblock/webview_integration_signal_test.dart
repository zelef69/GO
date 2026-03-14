import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/adblock/adblock_engine_bridge.dart';
import 'package:go_play/features/adblock/core/adblock_config.dart';
import 'package:go_play/features/adblock/core/adblock_debug_logger.dart';
import 'package:go_play/features/adblock/core/adblock_manager.dart';
import 'package:go_play/features/adblock/core/cosmetic_filter_injector.dart';
import 'package:go_play/features/adblock/core/scriptlet_injector.dart';
import 'package:go_play/features/adblock/core/webview_integration.dart';
import 'package:go_play/features/adblock/models/adblock_rule.dart';
import 'package:go_play/features/domain_lock/domain_policy_service.dart';

void main() {
  group('WebViewAdblockIntegration signal state', () {
    late WebViewAdblockIntegration integration;

    setUp(() {
      final manager = AdblockManager(
        domainPolicyService: DomainPolicyService(),
        nativeEngineBridge: _FakeBridge(),
        fallbackEngineBridge: _FakeBridge(),
        initialConfig: AdblockConfig.defaults(enabled: true, debugMode: false),
      );
      integration = WebViewAdblockIntegration(
        manager: manager,
        logger: AdblockDebugLogger(enabled: false),
        cosmeticFilterInjector: CosmeticFilterInjector(
          logger: AdblockDebugLogger(enabled: false),
        ),
        scriptletInjector: ScriptletInjector(
          logger: AdblockDebugLogger(enabled: false),
        ),
        initialConfig: AdblockConfig.defaults(enabled: true, debugMode: false),
      );
    });

    test('tracks ad signal and stall state per video key', () {
      final watchUri = Uri.parse('https://m.youtube.com/watch?v=video1');
      integration.onMainFrameChanged(watchUri);

      integration.updatePlaybackDebugSignal(<String, dynamic>{
        'event': 'video:waiting',
        'videoId': 'video1',
        'adShowing': true,
        'adInterrupting': false,
        'hasAdOverlay': false,
        'readyState': 0,
        'networkState': 2,
      }, pageUri: watchUri);

      final requestUri = Uri.parse(
        'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123',
      );
      expect(
        integration.isAdSignalActiveForRequest(requestUri, sourceUri: watchUri),
        isTrue,
      );
      expect(
        integration.isPlaybackStalledForRequest(
          requestUri,
          sourceUri: watchUri,
        ),
        isTrue,
      );

      integration.updatePlaybackDebugSignal(<String, dynamic>{
        'event': 'video:canplay',
        'videoId': 'video1',
        'adShowing': false,
        'adInterrupting': false,
        'hasAdOverlay': false,
        'readyState': 3,
        'networkState': 2,
      }, pageUri: watchUri);

      expect(
        integration.isPlaybackStalledForRequest(
          requestUri,
          sourceUri: watchUri,
        ),
        isFalse,
      );
    });

    test('keeps stall signal when readyState is 2 but buffer is empty', () {
      final watchUri = Uri.parse('https://m.youtube.com/watch?v=video1');
      integration.onMainFrameChanged(watchUri);

      integration.updatePlaybackDebugSignal(<String, dynamic>{
        'event': 'video:waiting',
        'videoId': 'video1',
        'adShowing': false,
        'adInterrupting': false,
        'hasAdOverlay': false,
        'readyState': 2,
        'networkState': 2,
        'currentTimeMs': 32000,
        'bufferedAheadMs': 0,
        'paused': false,
        'ended': false,
      }, pageUri: watchUri);

      final requestUri = Uri.parse(
        'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123',
      );
      expect(
        integration.isPlaybackStalledForRequest(
          requestUri,
          sourceUri: watchUri,
        ),
        isTrue,
      );

      integration.updatePlaybackDebugSignal(<String, dynamic>{
        'event': 'tick',
        'videoId': 'video1',
        'adShowing': false,
        'adInterrupting': false,
        'hasAdOverlay': false,
        'readyState': 2,
        'networkState': 2,
        'currentTimeMs': 34200,
        'bufferedAheadMs': 0,
        'paused': false,
        'ended': false,
      }, pageUri: watchUri);

      expect(
        integration.isPlaybackStalledForRequest(
          requestUri,
          sourceUri: watchUri,
        ),
        isTrue,
      );

      integration.updatePlaybackDebugSignal(<String, dynamic>{
        'event': 'video:playing',
        'videoId': 'video1',
        'adShowing': false,
        'adInterrupting': false,
        'hasAdOverlay': false,
        'readyState': 3,
        'networkState': 2,
        'currentTimeMs': 36000,
        'bufferedAheadMs': 1800,
        'paused': false,
        'ended': false,
      }, pageUri: watchUri);

      expect(
        integration.isPlaybackStalledForRequest(
          requestUri,
          sourceUri: watchUri,
        ),
        isFalse,
      );
    });

    test(
      'keeps ad signal for googlevideo requests even when source is youtube root',
      () {
        final watchUri = Uri.parse('https://m.youtube.com/watch?v=video1');
        final genericSource = Uri.parse('https://m.youtube.com/');
        integration.onMainFrameChanged(watchUri);

        integration.updatePlaybackDebugSignal(<String, dynamic>{
          'event': 'video:waiting',
          'videoId': 'video1',
          'adShowing': true,
          'adInterrupting': false,
          'hasAdOverlay': true,
          'readyState': 0,
          'networkState': 2,
        }, pageUri: watchUri);

        final requestUri = Uri.parse(
          'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123',
        );
        expect(
          integration.isAdSignalActiveForRequest(
            requestUri,
            sourceUri: genericSource,
          ),
          isTrue,
        );
      },
    );

    test(
      'clears stale ad signal after repeated stall pulses without ad markers',
      () {
        final watchUri = Uri.parse('https://m.youtube.com/watch?v=video1');
        integration.onMainFrameChanged(watchUri);

        integration.updatePlaybackDebugSignal(<String, dynamic>{
          'event': 'video:waiting',
          'videoId': 'video1',
          'adShowing': true,
          'adInterrupting': false,
          'hasAdOverlay': false,
          'readyState': 0,
          'networkState': 2,
        }, pageUri: watchUri);

        final requestUri = Uri.parse(
          'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123',
        );
        expect(
          integration.isAdSignalActiveForRequest(
            requestUri,
            sourceUri: watchUri,
          ),
          isTrue,
        );

        for (var index = 0; index < 4; index += 1) {
          integration.updatePlaybackDebugSignal(<String, dynamic>{
            'event': 'video:waiting',
            'videoId': 'video1',
            'adShowing': false,
            'adInterrupting': false,
            'hasAdOverlay': false,
            'readyState': 0,
            'networkState': 2,
          }, pageUri: watchUri);
        }

        expect(
          integration.isAdSignalActiveForRequest(
            requestUri,
            sourceUri: watchUri,
          ),
          isFalse,
        );
      },
    );

    test('clears stale signals when main frame switches to another video', () {
      final firstWatch = Uri.parse('https://m.youtube.com/watch?v=video1');
      final secondWatch = Uri.parse('https://m.youtube.com/watch?v=video2');
      integration.onMainFrameChanged(firstWatch);

      integration.updatePlaybackDebugSignal(<String, dynamic>{
        'event': 'video:waiting',
        'videoId': 'video1',
        'adShowing': true,
        'adInterrupting': false,
        'hasAdOverlay': false,
        'readyState': 0,
        'networkState': 2,
      }, pageUri: firstWatch);

      final requestUri = Uri.parse(
        'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123',
      );
      expect(
        integration.isAdSignalActiveForRequest(
          requestUri,
          sourceUri: firstWatch,
        ),
        isTrue,
      );

      integration.onMainFrameChanged(secondWatch);

      expect(
        integration.isAdSignalActiveForRequest(
          requestUri,
          sourceUri: firstWatch,
        ),
        isFalse,
      );
    });
  });
}

class _FakeBridge implements AdblockEngineBridge {
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
    return false;
  }

  @override
  Future<AdblockEngineRequestResult> evaluateRequestDetailed(
    Uri uri, {
    required String resourceType,
    Uri? sourceUrl,
  }) async {
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
