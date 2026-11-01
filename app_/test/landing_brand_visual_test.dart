import 'dart:io';
import 'package:cloud_storage/app_theme.dart';
import 'package:cloud_storage/src/authentication/landing_page.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
  for (final width in [390.0, 1440.0]) {
    for (final dark in [false, true]) {
      testWidgets('landing brand at $width dark=$dark', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            home: RepaintBoundary(
              key: key,
              child: LandingPage(
                auth: MockFirebaseAuth(),
                firestore: FakeFirebaseFirestore(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle(const Duration(seconds: 1));
        await tester.runAsync(
          () => precacheImage(
            const AssetImage(
              'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png',
            ),
            tester.element(find.byType(LandingPage)),
          ),
        );
        await tester.pump(const Duration(seconds: 5));
        expect(tester.takeException(), isNull);
        final bar = find.byType(AppBar);
        expect(
          find.descendant(of: bar, matching: find.text('RonikCloud')),
          findsNothing,
        );
        expect(
          find.descendant(of: bar, matching: find.byType(Image)),
          findsOneWidget,
        );
        expect(
          tester
              .getTopLeft(
                find.descendant(of: bar, matching: find.byType(Image)),
              )
              .dx,
          lessThan(30),
        );
        if (Platform.isWindows) {
          await expectLater(
            find.byKey(key),
            matchesGoldenFile(
              'goldens/windows/landing-brand-${width.toInt()}-${dark ? 'dark' : 'light'}.png',
            ),
          );
        }
      });
    }
  }
}
