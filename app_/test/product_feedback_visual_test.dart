import 'dart:io';
import 'package:cloud_storage/app_theme.dart';
import 'package:cloud_storage/src/support/product_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('Source Sans 3');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/SourceSans3-$weight.ttf'));
    }
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  for (final width in [390.0, 1440.0]) {
    for (final dark in [false, true]) {
      testWidgets('feedback layout at $width dark=$dark', (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            home: const Scaffold(),
          ),
        );
        tester
            .state<NavigatorState>(find.byType(Navigator))
            .push(
              MaterialPageRoute<void>(
                builder: (_) => RepaintBoundary(
                  key: key,
                  child: ProductFeedbackPage(onSubmit: (_) async {}),
                ),
              ),
            );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (Platform.isWindows) {
          await expectLater(
            find.byKey(key),
            matchesGoldenFile(
              'goldens/windows/feedback-${width.toInt()}-${dark ? 'dark' : 'light'}.png',
            ),
          );
        }
        if (width == 390) {
          await tester.tap(find.byType(TextField).first);
          await tester.pumpAndSettle();
          if (Platform.isWindows) {
            await expectLater(
              find.byKey(key),
              matchesGoldenFile(
                'goldens/windows/feedback-focused-${dark ? 'dark' : 'light'}.png',
              ),
            );
          }
        }
      });
    }
  }
  testWidgets('inline prompt wraps at narrow width with large text', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ProductFeedbackPrompt(
                  accountScope: 'visual:alice',
                  enabled: true,
                  onOpen: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (Platform.isWindows) {
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('goldens/windows/feedback-prompt-large-text.png'),
      );
    }
  });
}
