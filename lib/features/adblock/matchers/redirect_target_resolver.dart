import '../core/types.dart';

class RedirectTargetResolver {
  const RedirectTargetResolver();

  static final Map<String, String> _aliasTargets = <String, String>{
    'noopjs': Uri.dataFromString(
      '/* go_play adblock noopjs */',
      mimeType: 'application/javascript',
    ).toString(),
    'nooptext': Uri.dataFromString('', mimeType: 'text/plain').toString(),
    'noophtml': Uri.dataFromString(
      '<!doctype html><html><head></head><body></body></html>',
      mimeType: 'text/html',
    ).toString(),
    'blank-text': Uri.dataFromString('', mimeType: 'text/plain').toString(),
    'blank-html': Uri.dataFromString(
      '<!doctype html><html><head></head><body></body></html>',
      mimeType: 'text/html',
    ).toString(),
    'empty': Uri.dataFromString('', mimeType: 'text/plain').toString(),
  };

  String? resolve(String? rawTarget, {required RequestContext context}) {
    final target = (rawTarget ?? '').trim();
    if (target.isEmpty) {
      return null;
    }
    final normalized = target.toLowerCase();
    final alias = _aliasTargets[normalized];
    if (alias != null) {
      return alias;
    }
    if (normalized == 'about:blank') {
      return Uri.dataFromString(
        '<!doctype html><html><head></head><body></body></html>',
        mimeType: 'text/html',
      ).toString();
    }
    final parsed = Uri.tryParse(target);
    if (parsed != null && parsed.hasScheme) {
      return parsed.toString();
    }

    final base = context.frameUrl ?? context.topLevelUrl ?? context.url;
    try {
      final resolved = base.resolveUri(Uri.parse(target));
      return resolved.toString();
    } catch (_) {
      return null;
    }
  }
}

class RewriteTargetResolver {
  const RewriteTargetResolver();

  String? resolve(String? rawTarget, {required RequestContext context}) {
    final target = (rawTarget ?? '').trim();
    if (target.isEmpty) {
      return null;
    }
    final parsed = Uri.tryParse(target);
    if (parsed != null && parsed.hasScheme) {
      return parsed.toString();
    }
    final base = context.frameUrl ?? context.topLevelUrl ?? context.url;
    try {
      final resolved = base.resolveUri(Uri.parse(target));
      return resolved.toString();
    } catch (_) {
      return null;
    }
  }
}
