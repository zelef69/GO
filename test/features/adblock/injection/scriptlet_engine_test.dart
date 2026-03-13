import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/adblock/core/types.dart';
import 'package:go_play/features/adblock/filters/filter_compiler.dart';
import 'package:go_play/features/adblock/filters/filter_parser.dart';
import 'package:go_play/features/adblock/injection/scriptlet_engine.dart';

void main() {
  group('ScriptletEngine', () {
    const parser = FilterParser();
    const compiler = IndexedFilterCompiler();
    const engine = ScriptletEngine();

    test('resolves raw-script and +js rules for matching domain', () {
      const lines = <String>[
        'example.com##+js(set-constant, canRunAds, false)',
        r'example.com#$#window.__adblocked = true;',
      ];
      final parsed = parser.parse(lines);
      final compiled = compiler.compile(parsed: parsed, rawLines: lines);
      final context = PageContext(
        url: Uri.parse('https://example.com/home'),
        hostname: 'example.com',
        domain: 'example.com',
        topLevelUrl: Uri.parse('https://example.com/home'),
        headers: <String, String>{},
      );

      final payload = engine.resolvePayload(context, compiled);

      expect(payload.scripts.length, 2);
      expect(
        payload.scripts.any((s) => s.contains('window.__adblocked = true;')),
        isTrue,
      );
      expect(payload.scripts.any((s) => s.contains('set-constant')), isTrue);
      expect(payload.runtimeEnabled, isTrue);
    });

    test('adds default youtube recovery scriptlet for youtube pages', () {
      final parsed = parser.parse(const <String>[]);
      final compiled = compiler.compile(
        parsed: parsed,
        rawLines: const <String>[],
      );
      final context = PageContext(
        url: Uri.parse('https://m.youtube.com/watch?v=abc'),
        hostname: 'm.youtube.com',
        domain: 'youtube.com',
        topLevelUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
        headers: <String, String>{},
      );

      final payload = engine.resolvePayload(context, compiled);

      expect(payload.scripts, isNotEmpty);
      expect(
        payload.scripts.any(
          (script) => script.contains('__go_playScriptletInstalled'),
        ),
        isTrue,
      );
    });
  });
}
