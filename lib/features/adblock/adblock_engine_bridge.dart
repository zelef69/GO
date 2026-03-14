import 'dart:convert';

import '../../shared/constants/channel_constants.dart';
import '../../shared/platform/method_channel_client.dart';
import 'models/adblock_rule.dart';

class AdblockCosmeticResources {
  const AdblockCosmeticResources({
    required this.hideSelectors,
    required this.proceduralActions,
    required this.exceptions,
    required this.injectedScript,
    required this.generichide,
  });

  factory AdblockCosmeticResources.empty() {
    return const AdblockCosmeticResources(
      hideSelectors: <String>{},
      proceduralActions: <String>{},
      exceptions: <String>{},
      injectedScript: '',
      generichide: false,
    );
  }

  factory AdblockCosmeticResources.fromJson(Map<String, dynamic> json) {
    Set<String> toSet(String key) {
      final raw = json[key];
      if (raw is List<dynamic>) {
        return raw.map((entry) => entry.toString()).toSet();
      }
      return const <String>{};
    }

    return AdblockCosmeticResources(
      hideSelectors: toSet('hide_selectors'),
      proceduralActions: toSet('procedural_actions'),
      exceptions: toSet('exceptions'),
      injectedScript: json['injected_script']?.toString() ?? '',
      generichide: json['generichide'] == true,
    );
  }

  final Set<String> hideSelectors;
  final Set<String> proceduralActions;
  final Set<String> exceptions;
  final String injectedScript;
  final bool generichide;

  bool get isEmpty =>
      hideSelectors.isEmpty &&
      proceduralActions.isEmpty &&
      exceptions.isEmpty &&
      injectedScript.trim().isEmpty;
}

class AdblockEngineRequestResult {
  const AdblockEngineRequestResult({
    required this.blocked,
    required this.matched,
    required this.redirectDataUrl,
    required this.rewrittenUrl,
    required this.important,
    required this.exceptionRule,
    required this.matchedRule,
  });

  factory AdblockEngineRequestResult.allow() {
    return const AdblockEngineRequestResult(
      blocked: false,
      matched: false,
      redirectDataUrl: null,
      rewrittenUrl: null,
      important: false,
      exceptionRule: null,
      matchedRule: null,
    );
  }

  factory AdblockEngineRequestResult.fromJson(Map<String, dynamic> json) {
    final redirect = json['redirect']?.toString().trim();
    final redirectValue = (redirect == null || redirect.isEmpty)
        ? null
        : redirect;
    final exceptionRule = json['exception']?.toString().trim();
    final exceptionValue = (exceptionRule == null || exceptionRule.isEmpty)
        ? null
        : exceptionRule;
    final matched = json['matched'] == true;
    return AdblockEngineRequestResult(
      blocked: exceptionValue == null && (matched || redirectValue != null),
      matched: matched,
      redirectDataUrl: redirectValue,
      rewrittenUrl: json['rewritten_url']?.toString(),
      important: json['important'] == true,
      exceptionRule: exceptionValue,
      matchedRule: json['filter']?.toString(),
    );
  }

  final bool blocked;
  final bool matched;
  final String? redirectDataUrl;
  final String? rewrittenUrl;
  final bool important;
  final String? exceptionRule;
  final String? matchedRule;
}

abstract class AdblockEngineBridge {
  Future<bool> isAvailable();

  Future<void> initialize(
    List<AdblockRule> rules, {
    String? rawFilterText,
    String? resourcesJson,
    String? catalogSourcesJson,
    String? serializedEngineBase64,
    List<String> enabledTags,
  });

  Future<bool> shouldBlock(
    Uri uri, {
    required String resourceType,
    Uri? sourceUrl,
  });

  Future<AdblockEngineRequestResult> evaluateRequestDetailed(
    Uri uri, {
    required String resourceType,
    Uri? sourceUrl,
  });

  Future<AdblockCosmeticResources?> getCosmeticResources(Uri pageUri);

  Future<List<String>> getHiddenClassIdSelectors(
    Uri pageUri, {
    required List<String> classes,
    required List<String> ids,
    Set<String> exceptions,
  });

  Future<String?> getCspDirectives(
    Uri uri, {
    required String resourceType,
    Uri? sourceUrl,
  });

  Future<String?> serializeEngine();

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
  Future<void> initialize(
    List<AdblockRule> rules, {
    String? rawFilterText,
    String? resourcesJson,
    String? catalogSourcesJson,
    String? serializedEngineBase64,
    List<String> enabledTags = const <String>[],
  }) async {
    final filterText =
        rawFilterText ??
        rules.map((rule) => rule.rawRule).toList(growable: false).join('\n');
    final initialized = await _channelClient
        .invokeMethod<bool>('initializeEngine', <String, dynamic>{
          'rules': rules.map((rule) => rule.toJson()).toList(growable: false),
          'filterText': filterText,
          'resourcesJson': resourcesJson ?? '',
          'catalogSourcesJson': catalogSourcesJson ?? '[]',
          'serializedEngineBase64': serializedEngineBase64 ?? '',
          'enabledTags': enabledTags,
        });
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
    final payload = await _channelClient
        .invokeMethod<String>('evaluateRequestDetailed', <String, dynamic>{
          'url': uri.toString(),
          'resourceType': resourceType,
          'sourceUrl': sourceUrl?.toString() ?? '',
        });
    final raw = payload?.trim() ?? '';
    if (raw.isEmpty) {
      return AdblockEngineRequestResult.allow();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return AdblockEngineRequestResult.fromJson(decoded);
      }
      if (decoded is Map) {
        return AdblockEngineRequestResult.fromJson(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    } catch (_) {}
    return AdblockEngineRequestResult.allow();
  }

  @override
  Future<AdblockCosmeticResources?> getCosmeticResources(Uri pageUri) async {
    final payload = await _channelClient.invokeMethod<String>(
      'getCosmeticResources',
      <String, dynamic>{'url': pageUri.toString()},
    );
    final raw = payload?.trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final parsed = AdblockCosmeticResources.fromJson(decoded);
        if (!parsed.isEmpty) {
          return parsed;
        }
      } else if (decoded is Map) {
        final parsed = AdblockCosmeticResources.fromJson(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
        if (!parsed.isEmpty) {
          return parsed;
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<List<String>> getHiddenClassIdSelectors(
    Uri pageUri, {
    required List<String> classes,
    required List<String> ids,
    Set<String> exceptions = const <String>{},
  }) async {
    final payload = await _channelClient
        .invokeMethod<String>('getHiddenClassIdSelectors', <String, dynamic>{
          'url': pageUri.toString(),
          'classes': classes,
          'ids': ids,
          'exceptions': exceptions.toList(growable: false),
        });
    final raw = payload?.trim() ?? '';
    if (raw.isEmpty) {
      return const <String>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List<dynamic>) {
        return decoded
            .map((entry) => entry.toString().trim())
            .where((entry) => entry.isNotEmpty)
            .toList(growable: false);
      }
    } catch (_) {}
    return const <String>[];
  }

  @override
  Future<String?> getCspDirectives(
    Uri uri, {
    required String resourceType,
    Uri? sourceUrl,
  }) async {
    final payload = await _channelClient
        .invokeMethod<String>('getCspDirectives', <String, dynamic>{
          'url': uri.toString(),
          'resourceType': resourceType,
          'sourceUrl': sourceUrl?.toString() ?? '',
        });
    final text = payload?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  @override
  Future<String?> serializeEngine() async {
    final payload = await _channelClient.invokeMethod<String>(
      'serializeEngine',
    );
    final text = payload?.trim() ?? '';
    return text.isEmpty ? null : text;
  }
}

class DartAdblockEngineBridge implements AdblockEngineBridge {
  List<AdblockRule> _rules = const <AdblockRule>[];

  @override
  Future<void> dispose() async {
    _rules = const <AdblockRule>[];
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
    for (final rule in _rules) {
      if (rule.matches(uri)) {
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
