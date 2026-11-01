import 'package:flutter/services.dart';
import 'package:cloud_storage/app_theme.dart';
import 'package:cloud_storage/src/home/activity_center.dart';
import 'package:cloud_storage/src/shared/user_activity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<UserActivityStore> seed() async {
    SharedPreferences.setMockInitialValues({});
    final store = UserActivityStore(
      await SharedPreferences.getInstance(),
      uid: 'synthetic-a',
      scope: 'test',
    );
    await store.record(ActivityKind.backupProblem);
    return store;
  }

  for (final dark in [false, true]) {
    testWidgets(
      'activity visual review ${dark ? 'dark' : 'light'}',
      (tester) async {
        tester.view.physicalSize = dark
            ? const Size(390, 844)
            : const Size(1100, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final font = FontLoader('Source Sans 3')
          ..addFont(rootBundle.load('assets/fonts/SourceSans3-Regular.ttf'));
        await font.load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        final store = await seed();
        await store.record(ActivityKind.restoreVerified);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            home: ActivityCenterPage(
              store: store,
              isCurrentAccount: () => true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../../.audit/activity-${dark ? 'dark' : 'light'}.png',
          ),
        );
        expect(tester.takeException(), isNull);
      },
      skip: !const bool.fromEnvironment('ACTIVITY_CAPTURE'),
    );
  }
  testWidgets('narrow view and large text remain scrollable without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await seed();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: ActivityCenterPage(store: store, isCurrentAccount: () => true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Backup needs attention'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('tap returns a typed action only for the current account', (
    tester,
  ) async {
    final store = await seed();
    ActivityKind? selected;
    var current = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              selected = await Navigator.of(context).push<ActivityKind>(
                MaterialPageRoute(
                  builder: (_) => ActivityCenterPage(
                    store: store,
                    isCurrentAccount: () => current,
                  ),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    current = false;
    await tester.tap(find.text('Backup needs attention'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    current = true;
    await tester.tap(find.text('Backup needs attention'));
    await tester.pumpAndSettle();
    expect(selected, ActivityKind.backupProblem);
  });
  testWidgets('empty history never claims every file is protected', (
    tester,
  ) async {
    final store = await seed();
    await store.record(ActivityKind.backupProblem, resolved: true);
    await tester.pumpWidget(
      MaterialApp(
        home: ActivityCenterPage(store: store, isCurrentAccount: () => true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No recorded problems'), findsOneWidget);
    expect(find.textContaining('not proof that every file'), findsOneWidget);
    expect(find.text('Backup needs attention — resolved'), findsOneWidget);
  });
}
