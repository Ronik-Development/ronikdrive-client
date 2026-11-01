import 'dart:convert';
import 'package:cloud_storage/src/shared/user_activity.dart';
import 'package:cloud_storage/src/shared/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late UserActivityStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = UserActivityStore(
      prefs,
      uid: 'synthetic-account-a',
      scope: 'test-project',
    );
  });
  test(
    'deduplicates concurrent failures and only resolves an existing event',
    () async {
      expect(
        await store.record(ActivityKind.backupProblem, resolved: true),
        isFalse,
      );
      final results = await Future.wait(
        List.generate(30, (_) => store.record(ActivityKind.backupProblem)),
      );
      expect(results.where((changed) => changed).length, 1);
      expect(store.entries.length, 1);
      expect(
        await store.record(ActivityKind.backupProblem, resolved: true),
        isTrue,
      );
      expect(store.entry(ActivityKind.backupProblem)!.resolved, isTrue);
      expect(await store.record(ActivityKind.backupProblem), isTrue);
    },
  );
  test(
    'history and preferences survive reopening but never cross accounts or projects',
    () async {
      await store.record(ActivityKind.backgroundLocked);
      await store.saveSettings(const ActivityPreferences(problems: true));
      final reopened = UserActivityStore(
        prefs,
        uid: 'synthetic-account-a',
        scope: 'test-project',
      );
      expect(reopened.entries.single.kind, ActivityKind.backgroundLocked);
      expect(reopened.settings.problems, isTrue);
      for (final other in [
        UserActivityStore(
          prefs,
          uid: 'synthetic-account-b',
          scope: 'test-project',
        ),
        UserActivityStore(
          prefs,
          uid: 'synthetic-account-a',
          scope: 'another-project',
        ),
      ]) {
        expect(other.entries, isEmpty);
        expect(other.settings.problems, isFalse);
      }
    },
  );
  test(
    'persistence accepts only bounded codes, booleans and timestamps',
    () async {
      for (final kind in ActivityKind.values) {
        await store.record(kind);
      }
      expect(store.entries.length, ActivityKind.values.length);
      for (final key in prefs.getKeys()) {
        expect(key, isNot(contains('synthetic-account-a')));
        final value = jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;
        expect(value.keys.toSet(), {'at', 'resolved'});
        expect(value['at'], isA<int>());
        expect(value['resolved'], isA<bool>());
      }
    },
  );
  test('quiet hours, snooze and category opt-ins are independent', () {
    final day = DateTime(2026, 9, 28, 12);
    expect(
      const ActivityPreferences().allows(ActivityKind.backupProblem, day),
      isFalse,
    );
    const settings = ActivityPreferences(problems: true, quietHours: true);
    expect(settings.allows(ActivityKind.backupProblem, day), isTrue);
    expect(settings.allows(ActivityKind.restoreVerified, day), isFalse);
    expect(settings.allows(ActivityKind.securityChanged, day), isFalse);
    for (final hour in [0, 7, 22, 23]) {
      expect(
        settings.allows(
          ActivityKind.backupProblem,
          DateTime(2026, 9, 28, hour),
        ),
        isFalse,
      );
    }
    for (final hour in [8, 21]) {
      expect(
        settings.allows(
          ActivityKind.backupProblem,
          DateTime(2026, 9, 28, hour),
        ),
        isTrue,
      );
    }
    expect(
      settings
          .copyWith(snoozedUntil: day.add(const Duration(hours: 1)))
          .allows(ActivityKind.backupProblem, day),
      isFalse,
    );
  });
  test('recurrences have a persisted minimum alert interval', () async {
    await store.saveSettings(const ActivityPreferences(problems: true));
    final now = DateTime(2026, 9, 28, 12);
    expect(await store.claimAlert(ActivityKind.backupProblem, now), isTrue);
    expect(
      await store.claimAlert(
        ActivityKind.backupProblem,
        now.add(const Duration(minutes: 29)),
      ),
      isFalse,
    );
    expect(
      await store.claimAlert(
        ActivityKind.backupProblem,
        now.add(const Duration(minutes: 30)),
      ),
      isTrue,
    );
  });
  test(
    'native delivery failure cannot fail the backup or lose inbox history',
    () async {
      await store.saveSettings(const ActivityPreferences(problems: true));
      await NotificationService().record(store, ActivityKind.backupProblem);
      expect(store.entries.single.kind, ActivityKind.backupProblem);
    },
  );
}
