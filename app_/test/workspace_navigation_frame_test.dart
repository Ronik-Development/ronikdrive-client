import 'package:cloud_storage/src/home/workspace_navigation_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [360.0, 1440.0]) {
    testWidgets('workspace destinations work at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      int? selected;
      var settingsOpened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceNavigationFrame(
              selected: 0,
              nativeDriveLabel: 'File Explorer',
              onSelected: (value) => selected = value,
              onSettings: () => settingsOpened = true,
              backupsAvailable: true,
              account: const Text('Account avatar'),
              child: ListView(children: const [Text('File content')]),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('File content'), findsOneWidget);
      expect(find.text('RonikCloud'), findsNothing);
      expect(find.text('Account avatar'), findsOneWidget);
      if (width >= 1000) {
        expect(tester.getTopLeft(find.text('Account avatar')).dx,
            lessThan(tester.getTopLeft(find.text('File content')).dx));
      } else {
        expect(tester.getTopLeft(find.text('Account avatar')).dy,
            greaterThan(tester.getTopLeft(find.text('File content')).dy));
      }
      await tester.tap(find.text('Backups'));
      expect(selected, 1);
      await tester.tap(find.text('Offline'));
      expect(selected, 2);
      await tester.tap(find.text('File Explorer'));
      expect(selected, 3);
      await tester.tap(find.text('Settings'));
      expect(settingsOpened, isTrue);
      expect(selected, 3, reason: 'Settings must not reset the current section.');
    });
  }
  testWidgets('unsupported folder backups are not offered', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceNavigationFrame(
            selected: 0,
            onSelected: (_) {},
            onSettings: () {},
            backupsAvailable: false,
            child: const SizedBox(),
          ),
        ),
      ),
    );
    expect(find.text('Backups'), findsNothing);
    expect(find.text('Files'), findsOneWidget);
  });
}
