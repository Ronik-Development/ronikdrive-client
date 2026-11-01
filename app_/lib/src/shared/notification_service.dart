import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'user_activity.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();
  @visibleForTesting
  NotificationService.forTesting({
    this.deliveryDeadline = const Duration(seconds: 5),
  });
  Duration deliveryDeadline = const Duration(seconds: 5);
  Future<void> _deliveries = Future.value();
  final Map<String, int> _versions = {};
  String? _activeAccount;
  void bindAccount(String? account) {
    if (_activeAccount == account) return;
    _activeAccount = account;
    _versions.clear();
  }

  @visibleForTesting
  Future<void> get pendingDeliveries => _deliveries;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final _opens = StreamController<String>.broadcast();
  Stream<String> get opens => _opens.stream;
  String? _pendingAccount;
  Future<void>? _initialization;
  Future<void> initialize() => _initialization ??= _initialize()
      .timeout(deliveryDeadline)
      .catchError((Object error) {
        _initialization = null;
        throw error;
      });
  void _opened(String? payload) {
    if (payload == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(payload)) return;
    _pendingAccount = payload;
    _opens.add(payload);
  }

  bool takePending(String account) {
    if (_pendingAccount != account) return false;
    _pendingAccount = null;
    return true;
  }

  Future<void> _initialize() async {
    if (kIsWeb) return;
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: darwin,
        macOS: darwin,
        linux: LinuxInitializationSettings(
          defaultActionName: 'Open RonikCloud',
        ),
        windows: WindowsInitializationSettings(
          appName: 'RonikCloud',
          appUserModelId: 'com.ronikdrive.app',
          guid: '325f778d-69e1-4871-9311-209930f6063b',
        ),
      ),
      onDidReceiveNotificationResponse: (response) => _opened(response.payload),
    );
    final launch = await flutterLocalNotificationsPlugin
        .getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      _opened(launch?.notificationResponse?.payload);
    }
  }

  /// Called only following an explicit user action; denial never disables inbox.
  Future<bool?> requestPermission() async {
    if (kIsWeb) return false;
    try {
      await initialize();
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          return flutterLocalNotificationsPlugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission();
        case TargetPlatform.iOS:
          return flutterLocalNotificationsPlugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: false, sound: true);
        case TargetPlatform.macOS:
          return flutterLocalNotificationsPlugin
              .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: false, sound: true);
        default:
          return null; // Desktop permission status is controlled by the OS.
      }
    } catch (_) {
      return false;
    }
  }

  int _id(UserActivityStore store, ActivityKind kind) =>
      int.parse(store.account.substring(0, 6), radix: 16) * 16 + kind.index;
  Future<void> cancelAccount(UserActivityStore store) async {
    if (_activeAccount == store.account) bindAccount(null);
    if (kIsWeb) return;
    try {
      await initialize();
      await Future.wait(
        ActivityKind.values.map(
          (kind) => flutterLocalNotificationsPlugin
              .cancel(_id(store, kind))
              .timeout(deliveryDeadline),
        ),
      );
    } catch (_) {
      /* OS cleanup is best effort and bounded. */
    }
  }

  /// Notifications are best effort and must never fail a backup or restore.
  Future<void> record(
    UserActivityStore store,
    ActivityKind kind, {
    bool resolved = false,
    bool alert = true,
    bool Function()? accountCurrent,
  }) async {
    try {
      final changed = await store.record(kind, resolved: resolved);
      if (!changed || kIsWeb) return;
      bool owned() =>
          accountCurrent?.call() ??
          (_activeAccount == null || _activeAccount == store.account);
      if (!owned()) return;
      if (!resolved &&
          (!alert || !await store.claimAlert(kind, DateTime.now()))) {
        return;
      }
      final key = '${store.account}/${kind.index}';
      final version = (_versions[key] ?? 0) + 1;
      _versions[key] = version;
      final previous = _deliveries;
      final delivery = () async {
        try {
          await previous;
          if (!owned() || _versions[key] != version) return;
          await initialize();
          if (!owned() || _versions[key] != version) return;
          if (resolved) {
            await flutterLocalNotificationsPlugin
                .cancel(_id(store, kind))
                .timeout(deliveryDeadline);
            return;
          }
          await flutterLocalNotificationsPlugin
              .show(
                // Derive an OS notification ID; full account binding lives in payload.
                _id(store, kind),
                'RonikCloud',
                kind.informational
                    ? 'An account update is available. Open the app to review it.'
                    : 'Your backup or storage needs attention. Open the app to review it.',
                NotificationDetails(
                  android: AndroidNotificationDetails(
                    kind.informational
                        ? 'ronikcloud_updates_v1'
                        : 'ronikcloud_attention_v1',
                    kind.informational
                        ? 'Account updates'
                        : 'Problems needing attention',
                    importance: Importance.defaultImportance,
                    priority: Priority.defaultPriority,
                    visibility: NotificationVisibility.private,
                    onlyAlertOnce: true,
                  ),
                  iOS: const DarwinNotificationDetails(),
                  macOS: const DarwinNotificationDetails(),
                  linux: const LinuxNotificationDetails(),
                  windows: const WindowsNotificationDetails(),
                ),
                payload: store.account,
              )
              .timeout(deliveryDeadline);
        } catch (_) {
          /* Native delivery must not hold a protected operation. */
        }
      }();
      _deliveries = delivery;
      unawaited(delivery);
    } catch (_) {
      /* No raw exception logging or impact on protected operations. */
    }
  }
}
