import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/adblock/adblock_engine_bridge.dart';

void main() {
  group('AdblockEngineRequestResult.fromJson', () {
    test('treats redirect payload as blocking result', () {
      final result = AdblockEngineRequestResult.fromJson(<String, dynamic>{
        'matched': false,
        'redirect': 'data:text/plain,blocked',
      });

      expect(result.blocked, isTrue);
      expect(result.matched, isFalse);
      expect(result.redirectDataUrl, 'data:text/plain,blocked');
    });

    test('keeps rewritten url when provided', () {
      final result = AdblockEngineRequestResult.fromJson(<String, dynamic>{
        'matched': false,
        'rewritten_url': 'https://example.com/rewrite',
      });

      expect(result.blocked, isFalse);
      expect(result.rewrittenUrl, 'https://example.com/rewrite');
    });

    test('returns allow when no match and empty redirect', () {
      final result = AdblockEngineRequestResult.fromJson(<String, dynamic>{
        'matched': false,
        'redirect': '   ',
      });

      expect(result.blocked, isFalse);
      expect(result.redirectDataUrl, isNull);
    });

    test('honors exception rule even when matched is true', () {
      final result = AdblockEngineRequestResult.fromJson(<String, dynamic>{
        'matched': true,
        'exception': '@@||example.com^',
      });

      expect(result.blocked, isFalse);
      expect(result.exceptionRule, '@@||example.com^');
    });
  });
}
