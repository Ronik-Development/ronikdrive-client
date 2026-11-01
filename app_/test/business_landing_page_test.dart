import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_storage/app_theme.dart';
import 'package:cloud_storage/main.dart';
import 'package:cloud_storage/src/authentication/account_environment.dart';
import 'package:cloud_storage/src/authentication/business_landing_page.dart';
import 'package:cloud_storage/src/authentication/landing_page.dart';
import 'package:cloud_storage/src/authentication/login_page.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/firebase_test_auth.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    final font = FontLoader('Source Sans 3');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/SourceSans3-$weight.ttf'));
    }
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets(
    'workspace choices preserve environment and registration intent',
    (tester) async {
      final calls = <(AccountEnvironment, bool)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: BusinessLandingPage(
            openAccount: (environment, register) async {
              calls.add((environment, register));
            },
          ),
        ),
      );
      for (final entry in [
        ('business-create-account', AccountEnvironment.business, true),
        ('business-choose-personal', AccountEnvironment.personal, true),
        ('business-sign-in', AccountEnvironment.business, false),
      ]) {
        final action = find.byKey(ValueKey(entry.$1));
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pump();
        expect(calls.last, (entry.$2, entry.$3));
      }
      expect(calls, hasLength(3));
      expect(
        find.text('USD 6 monthly minimum, before tax'),
        findsOneWidget,
      );
      expect(find.textContaining('2 TB'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('account opening disables duplicate requests and allows retry', (
    tester,
  ) async {
    final opening = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: BusinessLandingPage(
          openAccount: (_, _) {
            calls++;
            return calls == 1 ? opening.future : Future.value();
          },
        ),
      ),
    );
    final action = find.byKey(const ValueKey('business-create-account'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pump();
    expect(tester.widget<FilledButton>(action).onPressed, isNull);
    opening.completeError(StateError('synthetic-private-provider-detail'));
    await tester.pump();
    expect(
      find.textContaining('Check your connection and try again.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('synthetic-private-provider-detail'),
      findsNothing,
    );
    await tester.tap(action);
    await tester.pump();
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('landing Business link opens the existing Business signup flow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: LandingPage(
          auth: TestFirebaseAuth(),
          firestore: FakeFirebaseFirestore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final link = find.byKey(const ValueKey('landing-business-link'));
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.byType(BusinessLandingPage), findsOneWidget);
    final action = find.byKey(const ValueKey('business-create-account'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    final login = tester.widget<LoginPage>(find.byType(LoginPage));
    expect(login.initialEnvironment, AccountEnvironment.business);
    expect(login.initialRegisterMode, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('public Business route renders while Firebase is still pending', (
    tester,
  ) async {
    final initialization = Completer<FirebaseApp>();
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/business';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    await tester.pumpWidget(
      CloudStorageApp(firebaseAppFuture: initialization.future),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(initialization.isCompleted, isFalse);
    expect(find.byType(BusinessLandingPage), findsOneWidget);
    expect(find.text('Which workspace fits your work?'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'direct Business route opens Business sign in with injected services',
    (tester) async {
      tester.binding.platformDispatcher.defaultRouteNameTestValue = '/business';
      addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
      );
      await tester.pumpWidget(
        CloudStorageApp(
          auth: TestFirebaseAuth(),
          firestore: FakeFirebaseFirestore(),
        ),
      );
      await tester.pumpAndSettle();
      final action = find.byKey(const ValueKey('business-sign-in'));
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      final login = tester.widget<LoginPage>(find.byType(LoginPage));
      expect(login.initialEnvironment, AccountEnvironment.business);
      expect(login.initialRegisterMode, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (width, scale, dark) in [
    (1440.0, 1.0, false),
    (390.0, 1.0, false),
    (390.0, 2.0, false),
    (1440.0, 2.0, false),
    (1440.0, 1.0, true),
  ]) {
    testWidgets('Business is readable at width=$width scale=$scale dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: RepaintBoundary(
            key: key,
            child: BusinessLandingPage(openAccount: (_, _) async {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_BUSINESS_PREVIEWS')) {
        await _capture(
          tester,
          key,
          'business-${width.toInt()}-${scale.toInt()}-${dark ? 'dark' : 'light'}-top',
        );
      }
      final action = find.byKey(const ValueKey('business-create-account'));
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      expect(action.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_BUSINESS_PREVIEWS')) {
        await _capture(
          tester,
          key,
          'business-${width.toInt()}-${scale.toInt()}-${dark ? 'dark' : 'light'}-choice',
        );
      }
      final footer = find.text('Back to RonikCloud');
      await tester.ensureVisible(footer);
      await tester.pumpAndSettle();
      expect(footer.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final directory = Directory('../.audit/business-previews');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  });
}
