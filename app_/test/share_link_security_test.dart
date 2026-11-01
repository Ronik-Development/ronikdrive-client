import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_storage/src/share/share_link_security.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'download proof is deterministic, scoped to token, and 256 bits',
    () async {
      final key = SecretKey(
        Uint8List.fromList(List<int>.generate(32, (index) => index)),
      );
      final first = await deriveShareDownloadProof(
        shareKey: key,
        token: 'share-token-a',
      );
      final retry = await deriveShareDownloadProof(
        shareKey: key,
        token: 'share-token-a',
      );
      final differentToken = await deriveShareDownloadProof(
        shareKey: key,
        token: 'share-token-b',
      );
      final differentKey = await deriveShareDownloadProof(
        shareKey: SecretKey(Uint8List(32)..fillRange(0, 32, 77)),
        token: 'share-token-a',
      );

      expect(first, retry);
      expect(base64Decode(first), hasLength(32));
      expect(differentToken, isNot(first));
      expect(differentKey, isNot(first));
      await expectLater(
        deriveShareDownloadProof(shareKey: key, token: '../unsafe'),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('share expiry is rounded up to an hour without shortening access', () {
    final rounded = coarseShareExpiry(
      now: DateTime.utc(2026, 8, 3, 12, 34, 56, 789),
      days: 7,
    );
    expect(rounded, DateTime.utc(2026, 8, 10, 13));
    expect(
      rounded.difference(DateTime.utc(2026, 8, 3, 12, 34, 56, 789)),
      allOf(
        greaterThanOrEqualTo(const Duration(days: 7)),
        lessThan(const Duration(days: 7, hours: 1)),
      ),
    );
    expect(
      coarseShareExpiry(now: DateTime.utc(2026, 8, 3, 12), days: 1),
      DateTime.utc(2026, 8, 4, 12),
    );
    expect(
      () => coarseShareExpiry(now: DateTime.utc(2026, 8, 3), days: 0),
      throwsRangeError,
    );
  });

  test(
    'owner summary exposes safety state without readable share metadata',
    () {
      final summary = ShareLinkOwnerSummary.fromMap(<String, dynamic>{
        'revoked': false,
        'expiresAt': '2026-08-09T12:00:00.000Z',
        'downloadCount': 3,
        'maxDownloads': 5,
        'lastAccessAt': '2026-08-02T08:00:00.000Z',
        'notifyOnAccess': true,
        'firstAccessNotifiedAt': '2026-08-02T08:00:00.000Z',
        'downloadProofFormat': shareDownloadProofFormat,
        'budgetWarningNotified': true,
        'proofAbuseNotified': true,
        'fileName': 'must-not-appear.pdf',
        'sourceFileId': 'must-not-appear',
        'recipientEmail': 'must-not-appear@example.test',
      });

      expect(summary.statusLabel(DateTime.utc(2026, 8, 2)), 'Active');
      expect(summary.requestCountLabel, contains('3 of 5'));
      expect(summary.proofLabel, contains('secret-derived proof is required'));
      expect(
        summary.alertLabel,
        'First-access alert sent. Exact access time is not retained.',
      );
      expect(summary.firstAccessNotified, isTrue);
      final rendered = <String>[
        summary.statusLabel(DateTime.utc(2026, 8, 2)),
        summary.requestCountLabel,
        summary.proofLabel,
        summary.alertLabel,
        summary.budgetAlertLabel,
        summary.abuseAlertLabel ?? '',
      ].join('\n');
      expect(rendered, isNot(contains('must-not-appear')));
    },
  );

  test('owner summary fails safe for limits, expiry, and legacy links', () {
    final limited = ShareLinkOwnerSummary.fromMap(<String, dynamic>{
      'downloadCount': 5,
      'maxDownloads': 5,
      'expiresAt': '2026-08-09T12:00:00.000Z',
    });
    expect(
      limited.statusLabel(DateTime.utc(2026, 8, 2)),
      'Download budget reached',
    );
    expect(limited.proofLabel, contains('Legacy link'));

    final expired = ShareLinkOwnerSummary.fromMap(<String, dynamic>{
      'expiresAt': '2026-08-01T12:00:00.000Z',
      'downloadCount': -1,
      'maxDownloads': 999999,
    });
    expect(expired.statusLabel(DateTime.utc(2026, 8, 2)), 'Expired');
    expect(expired.downloadCount, 0);
    expect(expired.maxDownloads, 0);
    expect(
      ShareLinkOwnerSummary.displayReference('very-secret-share-token'),
      allOf(startsWith('Share link - '), isNot(contains('very-secret'))),
    );
  });

  test('owner summary accepts the one-bit current alert state', () {
    final summary = ShareLinkOwnerSummary.fromMap(<String, dynamic>{
      'notifyOnAccess': true,
      'firstAccessNotified': true,
      'accessPrivacyVersion': 4,
    });

    expect(summary.firstAccessNotified, isTrue);
    expect(summary.alertLabel, contains('Exact access time is not retained'));
    expect(summary.budgetWarningNotified, isFalse);
    expect(summary.proofAbuseNotified, isFalse);
    expect(shareAccessPrivacyVersion, 4);
  });

  test('owner summary highlights generic proof abuse and budget alerts', () {
    final summary = ShareLinkOwnerSummary.fromMap(<String, dynamic>{
      'downloadCount': 8,
      'maxDownloads': 10,
      'downloadProofFormat': shareDownloadProofFormat,
      'budgetWarningNotified': true,
      'proofAbuseNotified': true,
    });

    expect(summary.requiresSecurityAttention, isTrue);
    expect(summary.budgetAlertLabel, contains('without file or recipient'));
    expect(summary.abuseAlertLabel, contains('were throttled'));
  });

  test('owner index derives active Personal and Business links locally', () {
    final index = ShareLinkOwnerIndex.fromMaps(<Map<String, dynamic>>[
      <String, dynamic>{
        'sourceFileId': 'personal-file',
        'expiresAt': '2026-08-09T12:00:00.000Z',
      },
      <String, dynamic>{
        'sourceFileId': 'business-file',
        'expiresAt': '2026-08-10T12:00:00.000Z',
      },
      <String, dynamic>{
        'sourceFileId': 'business-file',
        'expiresAt': '2026-08-11T12:00:00.000Z',
        'revoked': true,
      },
      <String, dynamic>{
        'sourceFileId': 'business-file',
        'expiresAt': '2026-08-12T12:00:00.000Z',
        'downloadCount': 2,
        'maxDownloads': 2,
      },
      <String, dynamic>{
        'sourceFileId': 'expired-file',
        'expiresAt': '2026-08-01T12:00:00.000Z',
      },
      <String, dynamic>{
        'sourceFileId': '',
        'expiresAt': '2026-08-13T12:00:00.000Z',
      },
    ]);
    final now = DateTime.utc(2026, 8, 2);

    expect(index.activeCountFor('personal-file', now), 1);
    expect(index.activeCountFor('business-file', now), 1);
    expect(index.activeCountFor('expired-file', now), 0);
    expect(index.activeCountFor('missing-file', now), 0);
    expect(index.nextExpiryAfter(now), DateTime.utc(2026, 8, 9, 12));
  });

  test('owner surfaces never render a precise password-share access time', () {
    final workspaceSource = File(
      'lib/src/home/workspace_home_page.dart',
    ).readAsStringSync();
    final dataSafetySource = File(
      'lib/src/home/data_safety_center_page.dart',
    ).readAsStringSync();
    final combined = '$workspaceSource\n$dataSafetySource';

    expect(combined, isNot(contains('Last encrypted payload request:')));
    expect(workspaceSource, contains('shareAccessPrivacyVersion'));
    expect(
      dataSafetySource,
      contains('The one-bit sent state prevents repeats'),
    );
    expect(dataSafetySource, contains('Emergency: revoke every link'));
    expect(dataSafetySource, contains('Enter a request budget from 1 to 1000'));
    expect(dataSafetySource, isNot(contains('Use 0 for no per-link budget')));
    expect(combined, contains('share-access timestamp is not retained'));
  });

  test('workspace derives share badges only from canonical owner links', () {
    final workspaceSource = File(
      'lib/src/home/workspace_home_page.dart',
    ).readAsStringSync();
    final supportingSource = File(
      'lib/src/home/workspace_home_page_supporting_types.dart',
    ).readAsStringSync();
    final dataSafetySource = File(
      'lib/src/home/data_safety_center_page.dart',
    ).readAsStringSync();
    final secureDriveSource = File(
      'lib/src/storage/secure_drive_service.dart',
    ).readAsStringSync();
    final shareDialogSource = File(
      'lib/src/share/share_link_dialogs.dart',
    ).readAsStringSync();

    expect(workspaceSource, contains(".collection('shared_links')"));
    expect(
      workspaceSource,
      contains(".where('uid', isEqualTo: widget.user.uid)"),
    );
    expect(workspaceSource, contains('ShareLinkOwnerIndex.fromMaps'));
    expect(workspaceSource, contains('Manage share links'));
    expect(workspaceSource, contains('Emergency: revoke every link'));
    expect(shareDialogSource, contains('int _budget = 10'));
    expect(
      workspaceSource,
      isNot(contains("value: 0, child: Text('No link budget')")),
    );
    expect(secureDriveSource, contains('maxDownloads.clamp(1, 1000)'));
    expect(
      workspaceSource,
      contains('creatorPersonalPrefix = _objectKeyOwnerPrefixes.first'),
    );
    expect(
      workspaceSource,
      contains('Source access is rechecked for every request'),
    );
    expect(
      shareDialogSource,
      contains('losing source sharing/download permission'),
    );
    expect(
      dataSafetySource,
      contains(
        'current Business membership plus share and download permission',
      ),
    );
    final shareCreateStart = workspaceSource.indexOf(
      "collection('shared_links').doc(token).set",
    );
    final shareCreateEnd = workspaceSource.indexOf(
      'final shareUrl =',
      shareCreateStart,
    );
    expect(shareCreateStart, greaterThanOrEqualTo(0));
    expect(shareCreateEnd, greaterThan(shareCreateStart));
    final shareCreate = workspaceSource.substring(
      shareCreateStart,
      shareCreateEnd,
    );
    expect(workspaceSource, contains('coarseShareExpiry'));
    final creator = workspaceSource.substring(
      workspaceSource.indexOf('Future<void> _createPasswordShareLink('),
      workspaceSource.indexOf('Future<void> _manageShareLinks('),
    );
    expect(
      creator.indexOf('isSupportedPublicShareSize(file.size)'),
      lessThan(creator.indexOf('_downloadFileBytes(')),
    );
    expect(
      creator.indexOf('isSupportedPublicShareSize(plainBytes.length)'),
      greaterThan(creator.indexOf('_downloadFileBytes(')),
    );
    expect(
      creator.indexOf('isSupportedPublicShareSize(plainBytes.length)'),
      lessThan(creator.indexOf('EncryptionService.instance.encryptData(')),
    );
    expect(shareCreate, isNot(contains("'createdAt'")));
    expect(shareCreate, isNot(contains("'revokedAt'")));
    expect(shareCreate, isNot(contains("'updatedAt'")));

    final policyStart = secureDriveSource.indexOf(
      'Future<void> updateSharePolicy',
    );
    final policyEnd = secureDriveSource.indexOf(
      '\n  Future<Map<String, dynamic>> _call',
      policyStart,
    );
    expect(policyStart, greaterThanOrEqualTo(0));
    expect(policyEnd, greaterThan(policyStart));
    final policyUpdate = secureDriveSource.substring(policyStart, policyEnd);
    final revokeStart = workspaceSource.indexOf(
      'Future<void> _handleManagedShareLinkAction',
    );
    final revokeEnd = workspaceSource.indexOf(
      '\n  Future<void> _toggleOffline',
      revokeStart,
    );
    expect(revokeStart, greaterThanOrEqualTo(0));
    expect(revokeEnd, greaterThan(revokeStart));
    final revokeUpdate = workspaceSource.substring(revokeStart, revokeEnd);
    for (final field in <String>[
      'createdAt',
      'revokedAt',
      'updatedAt',
      'lastAccessAt',
      'firstAccessNotifiedAt',
    ]) {
      expect(policyUpdate, contains("'$field': FieldValue.delete()"));
      expect(
        policyUpdate,
        isNot(contains("'$field': FieldValue.serverTimestamp()")),
      );
      expect(revokeUpdate, contains("'$field': FieldValue.delete()"));
      expect(
        revokeUpdate,
        isNot(contains("'$field': FieldValue.serverTimestamp()")),
      );
    }
    expect(
      workspaceSource,
      isNot(
        contains(
          "return '\$_objectKeyOwnerPrefix/shared/\$safeToken/payload.bin'",
        ),
      ),
    );
    expect(workspaceSource, isNot(contains("'shared': true")));
    expect(
      workspaceSource,
      isNot(contains("'sharedLinkCount': FieldValue.increment")),
    );
    expect(
      workspaceSource,
      isNot(contains("'lastSharedAt': FieldValue.serverTimestamp")),
    );
    expect(supportingSource, isNot(contains('sharedLinkCount')));
    expect(supportingSource, isNot(contains('lastSharedAt')));
  });
}
