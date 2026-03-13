import 'dart:convert';

import '../core/types.dart';
import '../filters/rule_models.dart';
import '../utils/tokenize.dart';

class ScriptletEngine {
  const ScriptletEngine();

  ScriptletPayload resolvePayload(PageContext context, CompiledFilterSet compiled) {
    if (compiled.scriptInjectionRules.isEmpty) {
      return _defaultPayloadForContext(context);
    }

    final candidates = <int>{};
    candidates.addAll(compiled.genericScriptletRuleIds);
    for (final token in tokenizeHostname(context.hostname)) {
      candidates.addAll(compiled.scriptletDomainIndex[token] ?? const <int>[]);
    }
    if (candidates.isEmpty) {
      return _defaultPayloadForContext(context);
    }

    final byId = compiled.scriptletRuleById();
    final scripts = <String>[];
    final seen = <String>{};
    final host = context.hostname.toLowerCase();
    final domain = context.domain.toLowerCase();

    for (final id in candidates) {
      final rule = byId[id];
      if (rule == null) {
        continue;
      }
      if (!_matchesDomainScope(rule, host, domain)) {
        continue;
      }
      final script = _resolveRuleScript(rule);
      if (script.isEmpty || !seen.add(script)) {
        continue;
      }
      scripts.add(script);
    }

    if (scripts.isEmpty) {
      return _defaultPayloadForContext(context);
    }
    final merged = <String>[...scripts];
    merged.addAll(_defaultScriptsForContext(context));
    final unique = <String>{};
    final ordered = <String>[];
    for (final script in merged) {
      final normalized = script.trim();
      if (normalized.isEmpty || !unique.add(normalized)) {
        continue;
      }
      ordered.add(normalized);
    }
    return ScriptletPayload(
      scripts: List<String>.unmodifiable(ordered),
      runtimeEnabled: true,
    );
  }

  InjectionScripts resolve(PageContext context, CompiledFilterSet compiled) {
    final payload = resolvePayload(context, compiled);
    return InjectionScripts(scripts: payload.scripts);
  }

  String _resolveRuleScript(ScriptInjectionRule rule) {
    if (rule.rawScript.trim().isNotEmpty) {
      return rule.rawScript.trim();
    }
    final scriptletName = rule.scriptletName.trim();
    if (scriptletName.isEmpty) {
      return '';
    }
    final argsJson = jsonEncode(rule.arguments);
    final nameJson = jsonEncode(scriptletName);
    return '''
(function() {
  try {
    if (window.__goPlayScriptlets &&
        typeof window.__goPlayScriptlets.run === 'function') {
      window.__goPlayScriptlets.run($nameJson, $argsJson);
    }
  } catch (_) {}
})();
''';
  }

  bool _matchesDomainScope(
    ScriptInjectionRule rule,
    String host,
    String domain,
  ) {
    if (rule.includeDomains.isNotEmpty) {
      var matchedInclude = false;
      for (final includeDomain in rule.includeDomains) {
        final normalized = includeDomain.toLowerCase();
        if (host == normalized ||
            host.endsWith('.$normalized') ||
            domain == normalized) {
          matchedInclude = true;
          break;
        }
      }
      if (!matchedInclude) {
        return false;
      }
    }
    for (final excludeDomain in rule.excludeDomains) {
      final normalized = excludeDomain.toLowerCase();
      if (host == normalized ||
          host.endsWith('.$normalized') ||
          domain == normalized) {
        return false;
      }
    }
    return true;
  }

  ScriptletPayload _defaultPayloadForContext(PageContext context) {
    final defaults = _defaultScriptsForContext(context);
    if (defaults.isEmpty) {
      return ScriptletPayload.empty(runtimeEnabled: true);
    }
    return ScriptletPayload(
      scripts: List<String>.unmodifiable(defaults),
      runtimeEnabled: true,
    );
  }

  List<String> _defaultScriptsForContext(PageContext context) {
    final host = context.hostname.toLowerCase();
    if (host == 'youtube.com' || host.endsWith('.youtube.com')) {
      return const <String>[_youtubeRecoveryScriptlet];
    }
    return const <String>[];
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
