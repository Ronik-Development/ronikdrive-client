import 'package:cloud_storage/src/security/file_collaboration_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cache fingerprints retain no readable collaboration text', () {
    const privateText = 'Quarterly acquisition details for person@example.test';
    final first = fileCollaborationCacheFingerprint(<Object?>[
      'legacy',
      privateText,
      'reviewer',
    ]);
    final repeated = fileCollaborationCacheFingerprint(<Object?>[
      'legacy',
      privateText,
      'reviewer',
    ]);
    final changed = fileCollaborationCacheFingerprint(<Object?>[
      'legacy',
      '$privateText changed',
      'reviewer',
    ]);

    expect(first, repeated);
    expect(first, isNot(changed));
    expect(first, hasLength(64));
    expect(first, isNot(contains('Quarterly')));
    expect(first, isNot(contains('person@example.test')));
  });

  test('oversized invalid components are bounded before hashing', () {
    final firstOversized = List<String>.filled(
      fileCollaborationCacheMaxComponentCharacters + 1,
      'A',
    ).join();
    final secondOversized = List<String>.filled(
      fileCollaborationCacheMaxComponentCharacters + 1,
      'B',
    ).join();
    final first = fileCollaborationCacheFingerprint(<Object?>[firstOversized]);
    final second = fileCollaborationCacheFingerprint(<Object?>[
      secondOversized,
    ]);

    expect(first, second);
    expect(first, hasLength(64));
  });

  test('legacy review fingerprints bind every migration field', () {
    final first = fileCollaborationLegacyReviewFingerprint(
      fileId: 'file-1',
      reviewerUid: 'reviewer-1',
      status: 'approved',
      reviewerName: 'Reviewer',
      note: 'Original note',
    );
    final changed = fileCollaborationLegacyReviewFingerprint(
      fileId: 'file-1',
      reviewerUid: 'reviewer-1',
      status: 'approved',
      reviewerName: 'Reviewer',
      note: 'Changed note',
    );

    expect(first, hasLength(64));
    expect(
      first,
      '179e629ef37536693a1f680fe4be5eabac6489bede17927000256042baa03b79',
    );
    expect(first, isNot(changed));
    expect(first, isNot(contains('Original note')));
  });
}
