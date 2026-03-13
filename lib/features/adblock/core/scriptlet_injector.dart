import 'dart:collection';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../adblock_engine_bridge.dart';
import 'adblock_config.dart';
import 'adblock_debug_logger.dart';

class ScriptletInjector {
  ScriptletInjector({required AdblockDebugLogger logger}) : _logger = logger;

  static const int _maxInjectedPages = 120;

  final AdblockDebugLogger _logger;
  final LinkedHashSet<String> _injectedPageSignatures = LinkedHashSet<String>();
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

  Future<void> injectIfNeeded(
    InAppWebViewController controller, {
    required Uri? pageUri,
    AdblockCosmeticResources? nativeResources,
    bool force = false,
  }) async {
    await _setRuntimeEnabledFlag(
      controller,
      enabled: _config.enabled && _config.scriptletsEnabled,
    );
    if (!_config.enabled || !_config.scriptletsEnabled) {
      return;
    }

    final scriptlet = _scriptletFor(pageUri, nativeResources: nativeResources);
    if (scriptlet == null) {
      return;
    }

    final signature = _pageSignature(pageUri);
    if (!force &&
        signature != null &&
        _injectedPageSignatures.contains(signature)) {
      return;
    }

    try {
      await controller.evaluateJavascript(source: scriptlet);
      if (signature != null) {
        _rememberSignature(signature);
      }
    } catch (_) {
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

  String? _scriptletFor(
    Uri? pageUri, {
    AdblockCosmeticResources? nativeResources,
  }) {
    final injectedScript = nativeResources?.injectedScript.trim() ?? '';
    final chunks = <String>[];
    if (injectedScript.isNotEmpty) {
      chunks.add(injectedScript);
    }
    final host = pageUri?.host.toLowerCase() ?? '';
    if (host == 'youtube.com' || host.endsWith('.youtube.com')) {
      chunks.add(_youtubeRecoveryScriptlet);
    }
    if (chunks.isEmpty) {
      return null;
    }
    return chunks.join('\n');
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

const String _youtubeRecoveryScriptlet = '''
(function() {
  if (window.__go_playScriptletInstalled === true) {
    return;
  }
  window.__go_playScriptletInstalled = true;
  window.__go_playScriptletRuntimeEnabled = true;

  function clickFirst(selectors) {
    for (var i = 0; i < selectors.length; i++) {
      var node = document.querySelector(selectors[i]);
      if (!node) {
        continue;
      }
      try { node.click(); return true; } catch (_) {}
    }
    return false;
  }

  var skipSelectors = [
    '.ytp-ad-skip-button',
    '.ytp-ad-skip-button-modern',
    '.ytp-ad-skip-button-container button',
    '.ytp-ad-skip-button-slot button'
  ];
  var closeOverlaySelectors = [
    '.ytp-ad-overlay-close-button',
    '.ytp-ad-overlay-container button[aria-label*=Close]',
    '.ytp-ad-overlay-container button[aria-label*=close]'
  ];

  setInterval(function() {
    if (window.__go_playScriptletRuntimeEnabled !== true) {
      return;
    }
    clickFirst(skipSelectors);
    clickFirst(closeOverlaySelectors);
  }, 900);
})();
''';
