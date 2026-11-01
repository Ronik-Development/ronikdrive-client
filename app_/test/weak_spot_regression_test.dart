import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_storage/src/security/business_encryption_service.dart';
import 'package:cloud_storage/src/security/business_encryption_registry.dart';
import 'package:cloud_storage/src/security/business_recipient_trust.dart';
import 'package:cloud_storage/src/shared/user_activity.dart';
import 'package:cloud_storage/src/shared/notification_service.dart';
import 'package:cloud_storage/src/storage/transfer_journal.dart';
import 'package:cloud_storage/src/privacy/local_private_cache.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryKeys implements LocalPrivateCacheKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'verified directory substitution is rejected before file keys are created',
    () async {
      final service = BusinessEncryptionService(random: Random(20260930));
      final victim = await service.createIdentity(
        accountProtectionKey: SecretKey(List.filled(32, 9)),
      );
      final attacker = await service.createIdentity(
        accountProtectionKey: SecretKey(List.filled(32, 7)),
      );
      final signer = await Ed25519().newKeyPairFromSeed(List.filled(32, 42));
      addTearDown(signer.destroy);
      final approval = await BusinessRecipientApproval.sign(
        companyId: 'synthetic-company',
        revision: 1,
        members: [
          {
            'uid': 'synthetic-victim',
            'keyId': victim.keyId,
            'publicKeyBase64': victim.publicKeyBase64,
            'scopes': ['company_shared'],
          },
        ],
        keyPair: signer,
      );
      final trust = BusinessRecipientTrust(
        LocalPrivateCachePreferences(
          preferences: await SharedPreferences.getInstance(),
          uid: 'synthetic-victim',
          scope: 'review',
          codec: LocalPrivateCacheCodec(keyStore: MemoryKeys()),
        ),
        accountCurrent: () => true,
      );
      await trust.pinVerified(
        approval,
        verifiedFingerprint: approval.fingerprint,
      );
      final registry = BusinessEncryptionRegistry(
        recipientVerifier: (response, scope, recipients) =>
            trust.verifyRecipients(
              companyId: response['companyId'] as String,
              scope: scope,
              policy: response['recipientTrust'],
              recipients: recipients,
            ),
        callable: (name, data) async => {
          'companyId': 'synthetic-company',
          'recipientTrust': approval.toMap(),
          'eligibleCount': 1,
          'readyCount': 1,
          'missingUids': <String>[],
          'recipients': [
            {
              'uid': 'synthetic-victim',
              'keyId': attacker.keyId,
              'publicKeyBase64': attacker.publicKeyBase64,
            },
          ],
        },
      );
      await expectLater(
        registry.listRecipients(storageScope: 'company_shared'),
        throwsA(isA<RecipientTrustException>()),
      );
    },
  );
  test(
    'unchanged journal progress emits only the first change notification',
    () async {
      final journal = await TransferJournal.open(
        preferences: await SharedPreferences.getInstance(),
        uid: 'synthetic',
        scope: 'review',
        codec: LocalPrivateCacheCodec(keyStore: MemoryKeys()),
      );
      await journal.begin(
        id: 'synthetic-transfer',
        kind: TransferJournalKind.upload,
        label: 'Synthetic upload',
        totalBytes: 100,
      );
      var notifications = 0;
      journal.addListener(() => notifications++);
      final timings = <int>[];
      for (var i = 0; i < 30; i++) {
        final watch = Stopwatch()..start();
        await journal.updateProgress(
          'synthetic-transfer',
          transferredBytes: 50,
        );
        timings.add(watch.elapsedMicroseconds);
      }
      expect(notifications, 1);
      timings.sort();
      debugPrint(
        'JOURNAL_DUPLICATE_PROGRESS: ${jsonEncode({'repetitions': 30, 'notifications': notifications, 'medianMicroseconds': timings[15], 'p95Microseconds': timings[28], 'environment': 'synthetic in-memory preferences, not physical disk'})}',
      );
      journal.dispose();
    },
  );
  test(
    'stalled native delivery cannot delay the persisted activity record',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      final nativeShow = Completer<bool>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getNotificationAppLaunchDetails') {
              return {'notificationLaunchedApp': false};
            }
            if (call.method == 'show') return nativeShow.future;
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final store = UserActivityStore(
        await SharedPreferences.getInstance(),
        uid: 'synthetic',
        scope: 'review',
      );
      await store.saveSettings(const ActivityPreferences(problems: true));
      var completed = false;
      final service = NotificationService.forTesting(
        deliveryDeadline: const Duration(milliseconds: 50),
      );
      final operation = service
          .record(store, ActivityKind.backupProblem)
          .then((_) => completed = true);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(completed, true);
      await service.pendingDeliveries;
      expect(store.entries.single.kind, ActivityKind.backupProblem);
      nativeShow.complete(true);
      await operation;
      expect(completed, true);
      debugPrint(
        'NOTIFICATION_BLOCK: record completed independently; native delivery deadline expired safely.',
      );
    },
  );
  test(
    'byte-only journal progress does not notify listing lifecycle subscribers',
    () async {
      final journal = await TransferJournal.open(
        preferences: await SharedPreferences.getInstance(),
        uid: 'synthetic-lifecycle',
        codec: LocalPrivateCacheCodec(keyStore: MemoryKeys()),
      );
      await journal.begin(
        id: 'lifecycle',
        kind: TransferJournalKind.upload,
        label: 'Synthetic transfer',
        totalBytes: 100,
      );
      await journal.updateProgress('lifecycle', transferredBytes: 1);
      final initial = journal.entries;
      expect(identical(journal.entries, initial), true);
      var listingSignals = 0, progressSignals = 0;
      journal.lifecycle.addListener(() => listingSignals++);
      journal.addListener(() => progressSignals++);
      for (var i = 2; i < 32; i++) {
        await journal.updateProgress('lifecycle', transferredBytes: i);
        expect(journal.pendingCount, 1);
      }
      expect(progressSignals, 30);
      expect(listingSignals, 0);
      await journal.complete('lifecycle');
      expect(listingSignals, 1);
      expect(journal.pendingCount, 0);
      journal.dispose();
    },
  );
  test(
    'unapproved Business writes stay pending even without a multipart checkpoint',
    () async {
      final prefs = await SharedPreferences.getInstance(),
          codec = LocalPrivateCacheCodec(keyStore: MemoryKeys());
      final journal = await TransferJournal.open(
        preferences: prefs,
        uid: 'synthetic-paused',
        codec: codec,
      );
      await journal.begin(
        id: 'paused',
        kind: TransferJournalKind.upload,
        label: 'Synthetic',
        totalBytes: 100,
      );
      await journal.fail(
        'paused',
        const RecipientTrustException('Synthetic unapproved key'),
      );
      expect(journal.pendingCount, 1);
      expect(journal.entries.single.state, TransferJournalState.interrupted);
      final restored = await TransferJournal.open(
        preferences: prefs,
        uid: 'synthetic-paused',
        codec: codec,
      );
      expect(restored.pendingCount, 1);
      expect(restored.entries.single.lastError, contains('key verification'));
      journal.dispose();
      restored.dispose();
    },
  );
}
