import 'package:cloud_storage/src/desktop_drive/desktop_drive_setup_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('native access requires explicit consent before enabling', (
    tester,
  ) async {
    var enabled = false;
    var starts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DesktopDriveSetupTile(
              available: true,
              loadEnabled: () async => enabled,
              saveEnabled: (value) async {
                enabled = value;
              },
              loadStatus: () async => 'connected',
              startWorker: () async {
                starts++;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(find.textContaining('Secure storage stays inside'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(enabled, true);
    expect(starts, 1);
    expect(find.text('Pause native access'), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(enabled, false);
    expect(starts, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('unsupported builds expose no nonfunctional setup control', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: DesktopDriveSetupTile(available: false)),
      ),
    );
    expect(find.byType(FilledButton), findsNothing);
    expect(find.textContaining('Not enabled in this build.'), findsOneWidget);
  });
  testWidgets(
    'connected Explorer opens its account folder and reports open failures',
    (tester) async {
      var opens = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DesktopDriveSetupTile(
                available: true,
                loadEnabled: () async => true,
                loadStatus: () async => 'connected',
                openFolder: () async {
                  opens++;
                  throw StateError('unavailable');
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final open = find.text('Open in File Explorer');
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(opens, 1);
      expect(
        find.text(
          'The Explorer location is unavailable. Reconnect and try again.',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
