import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/adblock/crowd/models/learned_signature.dart';
import 'package:go_play/features/adblock/crowd/signature/signature_matcher.dart';

void main() {
  group('SignatureMatcher', () {
    const matcher = SignatureMatcher();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final signatures = <LearnedSignature>[
      LearnedSignature(
        sigHash:
            '1111111111111111111111111111111111111111111111111111111111111111',
        hostPattern: '*.googlevideo.com',
        pathPattern: '/videoplayback',
        resourceType: 'media',
        sourceHost: '*.youtube.com',
        markerKeys: const <String>['ad_break_id', 'ad_campaign'],
        requireAdSignal: true,
        state: LearnedSignatureState.active,
        source: LearnedSignatureSource.cloud,
        score: 92,
        confidence: 0.93,
        seenCount: 14,
        falsePositiveCount: 0,
        firstSeenAtMs: nowMs - 120000,
        lastSeenAtMs: nowMs - 5000,
        expireAtMs: nowMs + const Duration(days: 10).inMilliseconds,
        updatedAtMs: nowMs - 1000,
      ),
    ];

    test('is conservative when ad signal is missing', () {
      final match = matcher.match(
        signatures: signatures,
        uri: Uri.parse(
          'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&ad_break_id=pod01',
        ),
        resourceType: 'media',
        sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
        adShowing: false,
        playbackStalled: false,
        nowMs: nowMs,
      );

      expect(match.matched, isFalse);
    });

    test('is conservative during playback stall', () {
      final match = matcher.match(
        signatures: signatures,
        uri: Uri.parse(
          'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&ad_break_id=pod01',
        ),
        resourceType: 'media',
        sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
        adShowing: true,
        playbackStalled: true,
        nowMs: nowMs,
      );

      expect(match.matched, isFalse);
    });

    test('matches when all conservative conditions are satisfied', () {
      final match = matcher.match(
        signatures: signatures,
        uri: Uri.parse(
          'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&ad_campaign=cmp-1',
        ),
        resourceType: 'media',
        sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
        adShowing: true,
        playbackStalled: false,
        nowMs: nowMs,
      );

      expect(match.matched, isTrue);
      expect(match.reason, 'crowd_learned_signature');
      expect(match.sigHash, signatures.first.sigHash);
    });
  });
}
