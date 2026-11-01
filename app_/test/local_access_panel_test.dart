import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_storage/src/agent_access/local_access_panel_native.dart';
import 'package:cloud_storage/src/desktop_drive/drive_provider_protocol.dart';
import 'local_access_server_test.dart' show MemoryBackend;

class PanelBackend extends MemoryBackend {
  @override
  Future<List<ProviderItem>> list(String parentId) async => [root];
}

void main() {
  testWidgets(
    'ended session can restart with fresh backend and renewed consent',
    (tester) async {
      final backends = <PanelBackend>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalAccessTile(
              backendFactory: ({required stillEnabled}) async {
                final backend = PanelBackend();
                backends.add(backend);
                return backend;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Local agent and WebDAV access'));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pumpAndSettle();
      expect(backends.first.revoked, true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await tester.tap(find.text('New session'));
      await tester.pumpAndSettle();
      expect(backends.length, 2);
      expect(backends.last.revoked, false);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(backends.last.revoked, true);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('requires folder and consent, and revokes on close', (
    tester,
  ) async {
    final backend = PanelBackend();
    late Future<bool> Function() allowed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalAccessTile(
            backendFactory: ({required stillEnabled}) async {
              allowed = stillEnabled;
              return backend;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Local agent and WebDAV access'));
    await tester.pumpAndSettle();
    expect(await allowed(), true);
    expect(find.textContaining('can retain copies'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allowed').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(find.textContaining('Endpoint:'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(backend.revoked, true);
    expect(await allowed(), false);
    expect(tester.takeException(), isNull);
  });
}
