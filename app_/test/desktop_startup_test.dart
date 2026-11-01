import 'package:cloud_storage/src/home/backup_startup_tile.dart';
import 'package:cloud_storage/src/shared/desktop_startup_linux_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Linux login entry quotes spaces and protects field codes', () {
    final entry = linuxBackupStartupEntry('/opt/My Cloud/100% app');
    expect(
      entry,
      contains('Exec="/opt/My Cloud/100%% app" --background-backup-worker'),
    );
    expect(entry, contains('Terminal=false'));
    expect(
      () => linuxBackupStartupEntry('/tmp/app\nExec=evil'),
      throwsArgumentError,
    );
    expect(() => linuxBackupStartupEntry('relative/app'), throwsArgumentError);
  });
  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets('backup setup remains readable at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(child: BackupStartupTile()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Keep backups running'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Debug previews must never register an OS login item.
      expect(find.text('Start at login'), findsNothing);
    });
  }
}
