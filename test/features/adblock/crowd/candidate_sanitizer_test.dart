import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/adblock/crowd/signature/candidate_sanitizer.dart';

void main() {
  group('CrowdCandidateSanitizer', () {
    const sanitizer = CrowdCandidateSanitizer();

    test('produces stable sig hash for equivalent requests', () {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final first = sanitizer.sanitize(
        uri: Uri.parse(
          'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&ad_break_id=pod01&ad_campaign=cmp1',
        ),
        resourceType: 'media',
        sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
        adShowing: true,
        reason: 'engine_match',
        nowMs: nowMs,
      );
      final second = sanitizer.sanitize(
        uri: Uri.parse(
          'https://rr2---sn-abc.googlevideo.com/videoplayback?ad_campaign=cmp1&id=123&ad_break_id=pod01',
        ),
        resourceType: 'media',
        sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
        adShowing: true,
        reason: 'engine_match',
        nowMs: nowMs,
      );

      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(first!.sigHash, second!.sigHash);
      expect(
        first.markerKeys,
        containsAll(<String>['ad_break_id', 'ad_campaign']),
      );
    });

    test('rejects reason outside strict learning allowlist', () {
      final result = sanitizer.sanitize(
        uri: Uri.parse(
          'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&ad_break_id=pod01',
        ),
        resourceType: 'media',
        sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
        adShowing: true,
        reason: 'allowed',
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );

      expect(result, isNull);
    });
  });
}
