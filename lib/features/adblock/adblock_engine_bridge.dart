import '../../shared/constants/channel_constants.dart';
import '../../shared/platform/method_channel_client.dart';
import 'models/adblock_rule.dart';

abstract class AdblockEngineBridge {
  Future<bool> isAvailable();

  Future<void> initialize(List<AdblockRule> rules);

  Future<bool> shouldBlock(
    Uri uri, {
    required String resourceType,
    Uri? sourceUrl,
  });

  Future<void> dispose();
}

class NativeAdblockEngineBridge implements AdblockEngineBridge {
  NativeAdblockEngineBridge()
    : _channelClient = MethodChannelClient(ChannelConstants.adblock);

  final MethodChannelClient _channelClient;

  @override
  Future<void> dispose() async {
    await _channelClient.invokeMethod<bool>('disposeEngine');
  }

  @override
  Future<void> initialize(List<AdblockRule> rules) async {
    final initialized = await _channelClient.invokeMethod<bool>(
      'initializeEngine',
      <String, dynamic>{
        'rules': rules.map((rule) => rule.toJson()).toList(growable: false),
      },
    );
    if (initialized != true) {
      throw StateError('Native adblock-rust engine initialization failed');
    }
  }

  @override
  Future<bool> isAvailable() async {
    return await _channelClient.invokeMethod<bool>('isRustEngineAvailable') ??
        false;
  }

  @override
  Future<bool> shouldBlock(
    Uri uri, {
    required String resourceType,
    Uri? sourceUrl,
  }) async {
    return await _channelClient
            .invokeMethod<bool>('shouldBlockRequest', <String, dynamic>{
              'url': uri.toString(),
              'resourceType': resourceType,
              'sourceUrl': sourceUrl?.toString() ?? '',
            }) ??
        false;
  }
}

class DartAdblockEngineBridge implements AdblockEngineBridge {
  List<AdblockRule> _rules = const <AdblockRule>[];

  @override
  Future<void> dispose() async {
    _rules = const <AdblockRule>[];
  }

  @override
  Future<void> initialize(List<AdblockRule> rules) async {
    _rules = rules;
  }

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> shouldBlock(
    Uri uri, {
    required String resourceType,
    Uri? sourceUrl,
  }) async {
    for (final rule in _rules) {
      if (rule.matches(uri)) {
        return true;
      }
    }
    return false;
  }
}
