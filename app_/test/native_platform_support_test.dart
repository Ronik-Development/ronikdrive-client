import 'dart:async';

import 'package:cloud_storage/src/shared/native_platform_support.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native cloud availability includes the registered Linux adapters', () {
    for (final platform in TargetPlatform.values) {
      expect(
        supportsCloudRuntime(isWeb: false, platform: platform),
        platform != TargetPlatform.fuchsia,
        reason: '$platform',
      );
      expect(supportsCloudRuntime(isWeb: true, platform: platform), isTrue);
    }
  });

  testWidgets('unsupported native launch offers a retryable browser handoff', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      UnsupportedNativePlatformApp(openWebApp: () async => ++attempts > 1),
    );
    expect(find.text('Use RonikCloud in your browser'), findsOneWidget);
    await tester.tap(find.text('Open the web app'));
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be opened'), findsOneWidget);
    await tester.tap(find.text('Try opening the web app again'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.textContaining('could not be opened'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'browser handoff prevents duplicate launches and survives disposal',
    (tester) async {
      final launch = Completer<bool>();
      var attempts = 0;
      await tester.pumpWidget(
        UnsupportedNativePlatformApp(
          openWebApp: () {
            attempts++;
            return launch.future;
          },
        ),
      );
      await tester.tap(find.text('Open the web app'));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byWidgetPredicate((widget) => widget is FilledButton),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      launch.complete(true);
      await tester.pump();
      expect(attempts, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'browser fallback remains usable with large text in a short window',
    (tester) async {
      tester.view.physicalSize = const Size(320, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        UnsupportedNativePlatformApp(openWebApp: () async => true),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Open the web app'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an unresponsive browser handoff becomes retryable', (
    tester,
  ) async {
    final launch = Completer<bool>();
    await tester.pumpWidget(
      UnsupportedNativePlatformApp(openWebApp: () => launch.future),
    );
    await tester.tap(find.text('Open the web app'));
    await tester.pump(const Duration(seconds: 21));
    await tester.pumpAndSettle();
    expect(find.text('Try opening the web app again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
