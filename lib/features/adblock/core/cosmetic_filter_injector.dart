import 'dart:collection';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'adblock_config.dart';
import 'adblock_debug_logger.dart';

class CosmeticFilterInjector {
  CosmeticFilterInjector({required AdblockDebugLogger logger}) : _logger = logger;

  static const int _injectedSignatureLimit = 120;

  final AdblockDebugLogger _logger;
  final LinkedHashSet<String> _injectedPageSignatures = LinkedHashSet<String>();

  AdblockConfig _config = AdblockConfig.defaults(enabled: true, debugMode: false);

  void setConfig(AdblockConfig config) {
    _config = config;
    if (!config.cosmeticFilteringEnabled) {
      _injectedPageSignatures.clear();
    }
  }

  Future<void> injectIfNeeded(
    InAppWebViewController controller, {
    required Uri? pageUri,
    bool force = false,
  }) async {
    if (!_config.enabled || !_config.cosmeticFilteringEnabled) {
      if (force) {
        await _removeInjectedStyle(controller);
      }
      return;
    }

    final signature = _pageSignature(pageUri);
    if (!force && signature != null && _injectedPageSignatures.contains(signature)) {
      return;
    }

    final selectors = _selectorsFor(pageUri);
    if (selectors.isEmpty) {
      return;
    }

    final cssText = selectors.join(',\n');
    final script = _buildInjectScript(cssText);
    try {
      await controller.evaluateJavascript(source: script);
      if (signature != null) {
        _rememberSignature(signature);
      }
    } catch (_) {
      _logger.log('cosmetic injector failed host=${pageUri?.host ?? "unknown"}');
    }
  }

  Future<void> _removeInjectedStyle(InAppWebViewController controller) async {
    const script = '''
(function() {
  var style = document.getElementById('go_play-cosmetic-style');
  if (style && style.parentNode) {
    style.parentNode.removeChild(style);
  }
})();
''';
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
    if (_injectedPageSignatures.length > _injectedSignatureLimit) {
      _injectedPageSignatures.remove(_injectedPageSignatures.first);
    }
  }

  List<String> _selectorsFor(Uri? pageUri) {
    final host = pageUri?.host.toLowerCase() ?? '';
    if (host == 'youtube.com' || host.endsWith('.youtube.com')) {
      return const <String>[
        'ytd-display-ad-renderer',
        'ytd-promoted-video-renderer',
        'ytd-promoted-sparkles-web-renderer',
        'ytd-companion-slot-renderer',
        'ytd-ad-slot-renderer',
        'ytd-action-companion-ad-renderer',
        'ytd-player-legacy-desktop-watch-ads-renderer',
        'ytd-in-feed-ad-layout-renderer',
        'ytm-promoted-sparkles-web-renderer',
        'ytm-promoted-sparkles-text-search-renderer',
        'ytm-companion-ad-renderer',
        '#player-ads',
        '.video-ads',
      ];
    }
    return const <String>[];
  }

  String _buildInjectScript(String selectors) {
    final escapedCss = selectors
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n');
    return '''
(function() {
  var style = document.getElementById('go_play-cosmetic-style');
  if (!style) {
    style = document.createElement('style');
    style.id = 'go_play-cosmetic-style';
    document.documentElement.appendChild(style);
  }
  style.textContent = '$escapedCss {display:none !important;opacity:0 !important;pointer-events:none !important;height:0 !important;}';
})();
''';
  }
}
