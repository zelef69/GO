import 'dart:convert';
import 'dart:collection';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'adblock_config.dart';
import 'adblock_debug_logger.dart';
import 'types.dart';

class CosmeticFilterInjector {
  CosmeticFilterInjector({required AdblockDebugLogger logger})
    : _logger = logger;

  static const int _injectedSignatureLimit = 120;

  final AdblockDebugLogger _logger;
  final LinkedHashSet<String> _injectedPageSignatures = LinkedHashSet<String>();

  int _attemptCount = 0;
  int _appliedCount = 0;
  int _skippedCount = 0;
  int _failedCount = 0;
  int _totalInjectDurationMs = 0;
  int _lastInjectDurationMs = 0;
  int _lastPayloadSelectors = 0;
  int _lastPayloadProcedural = 0;
  int _lastPayloadExceptions = 0;

  AdblockConfig _config = AdblockConfig.defaults(
    enabled: true,
    debugMode: false,
  );

  void setConfig(AdblockConfig config) {
    _config = config;
    if (!config.cosmeticFilteringEnabled) {
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
    'lastPayloadSelectors': _lastPayloadSelectors,
    'lastPayloadProcedural': _lastPayloadProcedural,
    'lastPayloadExceptions': _lastPayloadExceptions,
  };

  Future<void> injectIfNeeded(
    InAppWebViewController controller, {
    required Uri? pageUri,
    CosmeticPayload? payload,
    Set<String> additionalHideSelectors = const <String>{},
    bool force = false,
  }) async {
    _attemptCount += 1;
    if (!_config.enabled || !_config.cosmeticFilteringEnabled) {
      _skippedCount += 1;
      if (force) {
        await _removeInjectedStyle(controller);
      }
      return;
    }

    final signature = _pageSignature(pageUri);
    if (!force &&
        signature != null &&
        _injectedPageSignatures.contains(signature)) {
      _skippedCount += 1;
      return;
    }

    final plan = _buildPlan(
      payload: payload,
      additionalHideSelectors: additionalHideSelectors,
    );
    _lastPayloadSelectors = plan.hideSelectors.length;
    _lastPayloadProcedural = plan.styleRules.length + plan.domActionScripts.length;
    _lastPayloadExceptions = payload?.exceptions.length ?? 0;
    if (plan.isEmpty) {
      _skippedCount += 1;
      return;
    }
    final script = _buildInjectScript(plan);
    final watch = Stopwatch()..start();
    try {
      await controller.evaluateJavascript(source: script);
      watch.stop();
      _appliedCount += 1;
      _lastInjectDurationMs = watch.elapsedMilliseconds;
      _totalInjectDurationMs += _lastInjectDurationMs;
      if (signature != null) {
        _rememberSignature(signature);
      }
      if (_config.debugMode) {
        _logger.log(
          'cosmetic inject host=${pageUri?.host ?? "unknown"} selectors=${plan.hideSelectors.length} procedural=${plan.styleRules.length + plan.domActionScripts.length} durationMs=$_lastInjectDurationMs',
        );
      }
    } catch (_) {
      watch.stop();
      _failedCount += 1;
      _lastInjectDurationMs = watch.elapsedMilliseconds;
      _totalInjectDurationMs += _lastInjectDurationMs;
      _logger.log(
        'cosmetic injector failed host=${pageUri?.host ?? "unknown"}',
      );
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

  _CosmeticInjectionPlan _buildPlan({
    CosmeticPayload? payload,
    Set<String> additionalHideSelectors = const <String>{},
  }) {
    final hideSelectors = <String>{};
    final styleRules = <_CssStyleRule>[];
    final domActionScripts = <String>[];
    final effectivePayload = payload ?? CosmeticPayload.empty();
    final exceptions = effectivePayload.exceptions;
    final generichide = effectivePayload.generichide;

    if (!effectivePayload.isEmpty) {
      hideSelectors.addAll(effectivePayload.hideSelectors);
      final procedural = _parseProceduralActions(
        effectivePayload.proceduralActions,
      );
      hideSelectors.addAll(procedural.hideSelectors);
      styleRules.addAll(procedural.styleRules);
      domActionScripts.addAll(procedural.domActionScripts);
    }
    if (!generichide) {
      hideSelectors.addAll(additionalHideSelectors);
    }

    hideSelectors.removeWhere(
      (selector) =>
          selector.trim().isEmpty || exceptions.contains(selector.trim()),
    );
    styleRules.removeWhere(
      (rule) =>
          rule.selector.trim().isEmpty ||
          exceptions.contains(rule.selector.trim()) ||
          rule.style.trim().isEmpty,
    );
    return _CosmeticInjectionPlan(
      hideSelectors: hideSelectors.toList(growable: false),
      styleRules: styleRules,
      domActionScripts: domActionScripts,
    );
  }

  String _buildInjectScript(_CosmeticInjectionPlan plan) {
    final cssRules = <String>[];
    if (plan.hideSelectors.isNotEmpty) {
      cssRules.add(
        '${plan.hideSelectors.join(',\n')} {display:none !important;opacity:0 !important;pointer-events:none !important;height:0 !important;}',
      );
    }
    for (final styleRule in plan.styleRules) {
      cssRules.add('${styleRule.selector} {${styleRule.style}}');
    }
    final cssText = cssRules.join('\n');
    final escapedCss = cssText
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n');
    final actionScript = plan.domActionScripts.join('\n');
    final escapedActionScript = actionScript
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n');
    final runDomActions = plan.domActionScripts.isNotEmpty
        ? '''
  try {
    var goPlayCosmeticRunner = function() {
      try { eval('$escapedActionScript'); } catch (_) {}
    };
    goPlayCosmeticRunner();
    if (window.__goPlayCosmeticActionInterval == null) {
      window.__goPlayCosmeticActionInterval = setInterval(goPlayCosmeticRunner, 900);
    }
  } catch (_) {}
'''
        : '';
    return '''
(function() {
  var style = document.getElementById('go_play-cosmetic-style');
  if (!style) {
    style = document.createElement('style');
    style.id = 'go_play-cosmetic-style';
    document.documentElement.appendChild(style);
  }
  style.textContent = '$escapedCss';
$runDomActions
})();
''';
  }

  _ProceduralParseResult _parseProceduralActions(Set<String> rawEntries) {
    final hideSelectors = <String>{};
    final styleRules = <_CssStyleRule>[];
    final domActionScripts = <String>[];
    for (final rawEntry in rawEntries) {
      final entry = rawEntry.trim();
      if (entry.isEmpty) {
        continue;
      }
      try {
        final decoded = jsonDecode(entry);
        if (decoded is! Map) {
          continue;
        }
        final map = decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        final selector = _extractSingleCssSelector(map['selector']);
        if (selector == null || selector.isEmpty) {
          continue;
        }
        final actionRaw = map['action'];
        if (actionRaw == null) {
          hideSelectors.add(selector);
          continue;
        }
        if (actionRaw is! Map) {
          hideSelectors.add(selector);
          continue;
        }
        final action = actionRaw.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        final type = action['type']?.toString().trim().toLowerCase() ?? '';
        final arg = action['arg']?.toString() ?? '';
        switch (type) {
          case 'style':
            if (arg.trim().isNotEmpty) {
              styleRules.add(_CssStyleRule(selector: selector, style: arg));
            }
            break;
          case 'remove':
            domActionScripts.add(_domRemoveScript(selector));
            break;
          case 'remove-attr':
            if (arg.trim().isNotEmpty) {
              domActionScripts.add(_domRemoveAttrScript(selector, arg.trim()));
            }
            break;
          case 'remove-class':
            if (arg.trim().isNotEmpty) {
              domActionScripts.add(_domRemoveClassScript(selector, arg.trim()));
            }
            break;
          default:
            hideSelectors.add(selector);
            break;
        }
      } catch (_) {}
    }
    return _ProceduralParseResult(
      hideSelectors: hideSelectors,
      styleRules: styleRules,
      domActionScripts: domActionScripts,
    );
  }

  String? _extractSingleCssSelector(dynamic selectorRaw) {
    if (selectorRaw is! List) {
      return null;
    }
    if (selectorRaw.length != 1) {
      return null;
    }
    final first = selectorRaw.first;
    if (first is! Map) {
      return null;
    }
    final operator = first.map((key, value) => MapEntry(key.toString(), value));
    final type = operator['type']?.toString().trim().toLowerCase() ?? '';
    if (type != 'css-selector') {
      return null;
    }
    return operator['arg']?.toString().trim();
  }

  String _domRemoveScript(String selector) {
    final escapedSelector = _escapeJsString(selector);
    return "document.querySelectorAll('$escapedSelector').forEach(function(n){try{n.remove();}catch(_){}});";
  }

  String _domRemoveAttrScript(String selector, String attr) {
    final escapedSelector = _escapeJsString(selector);
    final escapedAttr = _escapeJsString(attr);
    return "document.querySelectorAll('$escapedSelector').forEach(function(n){try{n.removeAttribute('$escapedAttr');}catch(_){}});";
  }

  String _domRemoveClassScript(String selector, String cls) {
    final escapedSelector = _escapeJsString(selector);
    final escapedClass = _escapeJsString(cls);
    return "document.querySelectorAll('$escapedSelector').forEach(function(n){try{n.classList.remove('$escapedClass');}catch(_){}});";
  }

  String _escapeJsString(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', ' ');
  }
}

class _CosmeticInjectionPlan {
  const _CosmeticInjectionPlan({
    required this.hideSelectors,
    required this.styleRules,
    required this.domActionScripts,
  });

  final List<String> hideSelectors;
  final List<_CssStyleRule> styleRules;
  final List<String> domActionScripts;

  bool get isEmpty =>
      hideSelectors.isEmpty && styleRules.isEmpty && domActionScripts.isEmpty;
}

class _CssStyleRule {
  const _CssStyleRule({required this.selector, required this.style});

  final String selector;
  final String style;
}

class _ProceduralParseResult {
  const _ProceduralParseResult({
    required this.hideSelectors,
    required this.styleRules,
    required this.domActionScripts,
  });

  final Set<String> hideSelectors;
  final List<_CssStyleRule> styleRules;
  final List<String> domActionScripts;
}
