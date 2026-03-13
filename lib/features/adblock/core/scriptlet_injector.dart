import 'dart:collection';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'adblock_config.dart';
import 'adblock_debug_logger.dart';
import 'types.dart';

class ScriptletInjector {
  ScriptletInjector({required AdblockDebugLogger logger}) : _logger = logger;

  static const int _maxInjectedPages = 120;

  final AdblockDebugLogger _logger;
  final LinkedHashSet<String> _injectedPageSignatures = LinkedHashSet<String>();

  int _attemptCount = 0;
  int _appliedCount = 0;
  int _skippedCount = 0;
  int _failedCount = 0;
  int _totalInjectDurationMs = 0;
  int _lastInjectDurationMs = 0;
  int _lastPayloadScriptCount = 0;
  int _lastPayloadChars = 0;
  AdblockConfig _config = AdblockConfig.defaults(
    enabled: true,
    debugMode: false,
  );

  void setConfig(AdblockConfig config) {
    _config = config;
    if (!config.scriptletsEnabled) {
      _injectedPageSignatures.clear();
    }
  }

  Map<String, dynamic> get debugSnapshot => <String, dynamic>{
    'attempts': _attemptCount,
    'applied': _appliedCount,
    'skipped': _skippedCount,
    'failed': _failedCount,
    'lastInjectDurationMs': _lastInjectDurationMs,
    'averageInjectDurationMs': _attemptCount == 0
        ? 0
        : _totalInjectDurationMs / _attemptCount,
    'lastPayloadScriptCount': _lastPayloadScriptCount,
    'lastPayloadChars': _lastPayloadChars,
  };

  Future<void> injectIfNeeded(
    InAppWebViewController controller, {
    required Uri? pageUri,
    ScriptletPayload? payload,
    bool force = false,
  }) async {
    _attemptCount += 1;
    final effectivePayload = payload ?? ScriptletPayload.empty();
    final runtimeEnabled =
        _config.enabled &&
        _config.scriptletsEnabled &&
        effectivePayload.runtimeEnabled;
    await _setRuntimeEnabledFlag(controller, enabled: runtimeEnabled);
    if (!runtimeEnabled) {
      _skippedCount += 1;
      return;
    }

    if (effectivePayload.scripts.isEmpty) {
      _skippedCount += 1;
      return;
    }
    final scriptlet = effectivePayload.scripts.join('\n');
    _lastPayloadScriptCount = effectivePayload.scripts.length;
    _lastPayloadChars = scriptlet.length;

    final signature = _pageSignature(pageUri);
    if (!force &&
        signature != null &&
        _injectedPageSignatures.contains(signature)) {
      _skippedCount += 1;
      return;
    }

    final watch = Stopwatch()..start();
    try {
      await controller.evaluateJavascript(source: scriptlet);
      watch.stop();
      _appliedCount += 1;
      _lastInjectDurationMs = watch.elapsedMilliseconds;
      _totalInjectDurationMs += _lastInjectDurationMs;
      if (signature != null) {
        _rememberSignature(signature);
      }
      if (_config.debugMode) {
        _logger.log(
          'scriptlet inject host=${pageUri?.host ?? "unknown"} scripts=${effectivePayload.scripts.length} chars=${scriptlet.length} durationMs=$_lastInjectDurationMs',
        );
      }
    } catch (_) {
      watch.stop();
      _failedCount += 1;
      _lastInjectDurationMs = watch.elapsedMilliseconds;
      _totalInjectDurationMs += _lastInjectDurationMs;
      _logger.log(
        'scriptlet injector failed host=${pageUri?.host ?? "unknown"}',
      );
    }
  }

  Future<void> _setRuntimeEnabledFlag(
    InAppWebViewController controller, {
    required bool enabled,
  }) async {
    final value = enabled ? 'true' : 'false';
    final script = 'window.__go_playScriptletRuntimeEnabled = $value;';
    try {
      await controller.evaluateJavascript(source: script);
    } catch (_) {}
  }

  String? _pageSignature(Uri? pageUri) {
    if (pageUri == null || pageUri.host.isEmpty) {
      return null;
    }
    return '${pageUri.host.toLowerCase()}${pageUri.path}';
  }

  void _rememberSignature(String signature) {
    _injectedPageSignatures.remove(signature);
    _injectedPageSignatures.add(signature);
    if (_injectedPageSignatures.length > _maxInjectedPages) {
      _injectedPageSignatures.remove(_injectedPageSignatures.first);
    }
  }
}
