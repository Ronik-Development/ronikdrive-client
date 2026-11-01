import 'dart:typed_data';

import 'package:cloud_storage/src/home/migration/cloud_drive_provider.dart';
import 'package:cloud_storage/src/home/migration/drive_migration_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('provider connection details never reach the migration overlay', (
    tester,
  ) async {
    const secret =
        'OAuth response for private@example.com at /private/photos/image.png';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DriveMigrationOverlay(
            providers: <CloudDriveProvider>[
              _FailingProvider(Exception(secret)),
            ],
            onImport: (_, _) async {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Test Drive'));
    await tester.pump();

    expect(
      find.text(
        'Could not connect to this storage provider. Check your sign-in and connection, then try again.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('private@example.com'), findsNothing);
    expect(find.textContaining('image.png'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _FailingProvider extends CloudDriveProvider {
  const _FailingProvider(this.failure);

  final Object failure;

  @override
  String get description => 'Import test files';

  @override
  String get displayName => 'Test Drive';

  @override
  IconData get icon => Icons.cloud_outlined;

  @override
  String get id => 'test';

  @override
  bool get isConnected => false;

  @override
  Future<RemoteFilePayload> download(RemoteFileEntry file) async =>
      RemoteFilePayload(bytes: Uint8List(0), sizeBytes: 0);

  @override
  Future<void> ensureAuthenticated(BuildContext context) async => throw failure;

  @override
  Future<List<RemoteEntry>> listChildren(RemoteFolderEntry? parent) async =>
      const <RemoteEntry>[];
}
