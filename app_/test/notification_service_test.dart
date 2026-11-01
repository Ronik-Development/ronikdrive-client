import 'dart:async';
import 'package:cloud_storage/src/shared/notification_service.dart';
import 'package:cloud_storage/src/shared/user_activity.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native delivery is generic, account-bound, deduplicated and canceled after resolution',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      final calls = <MethodCall>[];
      SharedPreferences.setMockInitialValues({});
      final store = UserActivityStore(
        await SharedPreferences.getInstance(),
        uid: 'private-account',
        scope: 'test',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'getNotificationAppLaunchDetails') {
              return {
                'notificationLaunchedApp': true,
                'notificationResponse': {
                  'notificationResponseType': 0,
                  'payload': store.account,
                },
              };
            }
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final service = NotificationService.forTesting();
      await Future.wait([service.initialize(), service.initialize()]);
      expect(calls.where((call) => call.method == 'initialize').length, 1);
      expect(service.takePending('other-account'), isFalse);
      expect(service.takePending(store.account), isTrue);
      expect(service.takePending(store.account), isFalse);
      await store.saveSettings(const ActivityPreferences(problems: true));
      await service.record(store, ActivityKind.backupProblem);
      await service.record(store, ActivityKind.backupProblem);
      await service.pendingDeliveries;
      final shown =
          calls.where((call) => call.method == 'show').single.arguments as Map;
      expect(shown['title'], 'RonikCloud');
      expect(
        shown['body'],
        'Your backup or storage needs attention. Open the app to review it.',
      );
      expect(shown['payload'], store.account);
      expect(shown.toString(), isNot(contains('private-account')));
      expect(
        (shown['platformSpecifics'] as Map)['channelId'],
        'ronikcloud_attention_v1',
      );
      await service.record(store, ActivityKind.backupProblem, resolved: true);
      await service.pendingDeliveries;
      expect(calls.where((call) => call.method == 'cancel').length, 1);
    },
  );
  test(
    'account change while native initialization is pending suppresses old delivery',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      final initialization = Completer<bool>(), started = Completer<void>();
      var shown = 0, current = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'initialize') {
              started.complete();
              return initialization.future;
            }
            if (call.method == 'getNotificationAppLaunchDetails') {
              return {'notificationLaunchedApp': false};
            }
            if (call.method == 'show') shown++;
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      SharedPreferences.setMockInitialValues({});
      final store = UserActivityStore(
        await SharedPreferences.getInstance(),
        uid: 'synthetic-notification-owner',
        scope: 'test',
      );
      await store.saveSettings(const ActivityPreferences(problems: true));
      final service = NotificationService.forTesting();
      service.bindAccount(store.account);
      await service.record(
        store,
        ActivityKind.backupProblem,
        accountCurrent: () => current,
      );
      await started.future.timeout(const Duration(seconds: 1));
      current = false;
      service.bindAccount('different-synthetic-account');
      initialization.complete(true);
      await service.pendingDeliveries;
      expect(shown, 0);
      expect(store.entries.length, 1);
    },
  );
}
