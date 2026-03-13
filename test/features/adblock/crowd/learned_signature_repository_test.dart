import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/adblock/crowd/models/learned_signature.dart';
import 'package:go_play/features/adblock/crowd/signature/candidate_sanitizer.dart';
import 'package:go_play/features/adblock/crowd/signature/signature_matcher.dart';
import 'package:go_play/features/adblock/crowd/storage/learned_signature_db.dart';
import 'package:go_play/features/adblock/crowd/storage/learned_signature_repository.dart';

void main() {
  group('LearnedSignatureRepository', () {
    test('merges local and cloud signature data conservatively', () async {
      final baseNow = DateTime.fromMillisecondsSinceEpoch(
        1730000000000,
        isUtc: true,
      );
      var now = baseNow;
      final repository = LearnedSignatureRepository(
        database: LearnedSignatureDb(),
        matcher: const SignatureMatcher(),
        now: () => now,
      );
      addTearDown(repository.dispose);
      await repository.initialize();

      const sanitizer = CrowdCandidateSanitizer();
      final candidate = sanitizer.sanitize(
        uri: Uri.parse(
          'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&ad_break_id=pod01',
        ),
        resourceType: 'media',
        sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
        adShowing: true,
        reason: 'engine_match',
        nowMs: now.millisecondsSinceEpoch,
      );
      expect(candidate, isNotNull);

      await repository.recordDecision(
        uri: Uri.parse(
          'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&ad_break_id=pod01',
        ),
        resourceType: 'media',
        sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
        adShowing: true,
        blocked: true,
        reason: 'engine_match',
      );

      now = now.add(const Duration(minutes: 3));
      await repository.applySnapshot(
        version: 2,
        checksum: 'snapshot-v2',
        signatures: <LearnedSignature>[
          LearnedSignature(
            sigHash: candidate!.sigHash,
            hostPattern: '*.googlevideo.com',
            pathPattern: '/videoplayback',
            resourceType: 'media',
            sourceHost: '*.youtube.com',
            markerKeys: const <String>['ad_break_id', 'ad_campaign'],
            requireAdSignal: true,
            state: LearnedSignatureState.active,
            source: LearnedSignatureSource.cloud,
            score: 91,
            confidence: 0.92,
            seenCount: 20,
            falsePositiveCount: 0,
            firstSeenAtMs: baseNow.millisecondsSinceEpoch - 300000,
            lastSeenAtMs: now.millisecondsSinceEpoch - 1000,
            expireAtMs:
                now.millisecondsSinceEpoch +
                const Duration(days: 30).inMilliseconds,
            updatedAtMs: now.millisecondsSinceEpoch - 500,
          ),
        ],
      );

      final match = repository.precheck(
        uri: Uri.parse(
          'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&ad_campaign=cmp1',
        ),
        resourceType: 'media',
        sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
        adShowing: true,
        playbackStalled: false,
      );
      expect(match.matched, isTrue);
    });

    test('quarantines signature after repeated playback stall feedback', () async {
      final fixedNow = DateTime.fromMillisecondsSinceEpoch(
        1730100000000,
        isUtc: true,
      );
      final repository = LearnedSignatureRepository(
        database: LearnedSignatureDb(),
        matcher: const SignatureMatcher(),
        now: () => fixedNow,
      );
      addTearDown(repository.dispose);
      await repository.initialize();

      const sigHash =
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      await repository.applySnapshot(
        version: 1,
        checksum: 'snapshot-v1',
        signatures: <LearnedSignature>[
          LearnedSignature(
            sigHash: sigHash,
            hostPattern: '*.googlevideo.com',
            pathPattern: '/videoplayback',
            resourceType: 'media',
            sourceHost: '*.youtube.com',
            markerKeys: const <String>['ad_break_id'],
            requireAdSignal: false,
            state: LearnedSignatureState.active,
            source: LearnedSignatureSource.cloud,
            score: 90,
            confidence: 0.9,
            seenCount: 18,
            falsePositiveCount: 0,
            firstSeenAtMs: fixedNow.millisecondsSinceEpoch - 100000,
            lastSeenAtMs: fixedNow.millisecondsSinceEpoch - 5000,
            expireAtMs:
                fixedNow.millisecondsSinceEpoch +
                const Duration(days: 20).inMilliseconds,
            updatedAtMs: fixedNow.millisecondsSinceEpoch - 1000,
          ),
        ],
      );

      for (var index = 0; index < 3; index += 1) {
        await repository.recordPlaybackStall(
          uri: Uri.parse(
            'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&ad_break_id=pod01',
          ),
          resourceType: 'media',
          sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
        );
      }

      final match = repository.precheck(
        uri: Uri.parse(
          'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&ad_break_id=pod01',
        ),
        resourceType: 'media',
        sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
        adShowing: true,
        playbackStalled: false,
      );
      expect(match.matched, isFalse);
    });

    test('expires cloud signature removed from newer snapshot', () async {
      final fixedNow = DateTime.fromMillisecondsSinceEpoch(
        1730200000000,
        isUtc: true,
      );
      final repository = LearnedSignatureRepository(
        database: LearnedSignatureDb(),
        matcher: const SignatureMatcher(),
        now: () => fixedNow,
      );
      addTearDown(repository.dispose);
      await repository.initialize();

      await repository.applySnapshot(
        version: 1,
        checksum: 'snapshot-v1',
        signatures: <LearnedSignature>[
          LearnedSignature(
            sigHash:
                'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
            hostPattern: '*.googlevideo.com',
            pathPattern: '/videoplayback',
            resourceType: 'media',
            sourceHost: '*.youtube.com',
            markerKeys: const <String>['ad_break_id'],
            requireAdSignal: true,
            state: LearnedSignatureState.active,
            source: LearnedSignatureSource.cloud,
            score: 89,
            confidence: 0.9,
            seenCount: 12,
            falsePositiveCount: 0,
            firstSeenAtMs: fixedNow.millisecondsSinceEpoch - 100000,
            lastSeenAtMs: fixedNow.millisecondsSinceEpoch - 1000,
            expireAtMs:
                fixedNow.millisecondsSinceEpoch +
                const Duration(days: 20).inMilliseconds,
            updatedAtMs: fixedNow.millisecondsSinceEpoch - 1000,
          ),
        ],
      );

      await repository.applySnapshot(
        version: 2,
        checksum: 'snapshot-v2',
        signatures: const <LearnedSignature>[],
      );

      final match = repository.precheck(
        uri: Uri.parse(
          'https://rr2---sn-abc.googlevideo.com/videoplayback?id=123&ad_break_id=pod01',
        ),
        resourceType: 'media',
        sourceUrl: Uri.parse('https://m.youtube.com/watch?v=abc'),
        adShowing: true,
        playbackStalled: false,
      );
      expect(match.matched, isFalse);
    });
  });
}
