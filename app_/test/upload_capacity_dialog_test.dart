import 'dart:io';
import 'package:cloud_storage/app_theme.dart';
import 'package:cloud_storage/src/storage/upload_capacity_dialog.dart';
import 'package:cloud_storage/src/storage/upload_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('Source Sans 3')
          ..addFont(rootBundle.load('assets/fonts/SourceSans3-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/SourceSans3-SemiBold.ttf')))
        .load();
  });
  for (final width in [320.0, 1200.0]) {
    for (final dark in [false, true]) {
      testWidgets('quota dialog at $width dark=$dark', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final root = GlobalKey();
        UploadCapacityAction? choice;
        await tester.pumpWidget(
          RepaintBoundary(
            key: root,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark ? AppTheme.dark() : AppTheme.light(),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () async {
                      choice = await showUploadCapacityDialog(
                        context,
                        UploadCapacityDecision({
                          'capacityBytes': 1073741824,
                          'usageBytes': 800000000,
                          'reservedBytes': 100000000,
                          'selectedBytes': 300000000,
                          'shortfallBytes': 126258176,
                        }),
                      );
                    },
                    child: const Text('Upload'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Upload'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Upgrade and continue'), findsOneWidget);
        expect(find.text('Choose fewer files'), findsOneWidget);
        if (Platform.isWindows) {
          await expectLater(
            find.byKey(root),
            matchesGoldenFile(
              'goldens/windows/upload-quota-${width.toInt()}-${dark ? 'dark' : 'light'}.png',
            ),
          );
        }
        await tester.tap(find.text('Choose fewer files'));
        await tester.pumpAndSettle();
        expect(choice, UploadCapacityAction.chooseFewer);
      });
    }
  }
}
