import 'package:cloud_storage/src/home/folder_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const folders = <SimpleFolder>[
    SimpleFolder(id: 'clients', name: 'Clients'),
    SimpleFolder(id: 'archive', name: 'Archive'),
    SimpleFolder(id: 'reports', name: 'Reports', parentId: 'clients'),
    SimpleFolder(id: 'drafts', name: 'Drafts', parentId: 'reports'),
  ];

  testWidgets('can navigate from nested initial folder back to root siblings', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FolderPicker(
          folders: folders,
          movingFolderIds: const <String>{},
          initialParentId: 'reports',
        ),
      ),
    );

    expect(find.text('Drafts'), findsOneWidget);
    expect(find.text('Archive'), findsNothing);

    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Archive'), findsNothing);

    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Clients'), findsOneWidget);
  });

  testWidgets('disables selected folder descendants as destinations', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FolderPicker(
          folders: folders,
          movingFolderIds: const <String>{'reports'},
          initialParentId: 'clients',
        ),
      ),
    );

    final reportsTile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Reports'),
    );
    expect(reportsTile.enabled, isFalse);

    await tester.tap(find.text('Move here'));
    await tester.pumpAndSettle();
  });
}
