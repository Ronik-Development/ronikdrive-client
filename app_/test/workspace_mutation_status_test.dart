import 'dart:io';

import 'package:cloud_storage/src/home/workspace_mutation_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classifyWorkspaceMutationFailure', () {
    test('keeps a confirmed single-record rejection retryable', () {
      final failure = classifyWorkspaceMutationFailure(
        action: WorkspaceMutationAction.renameFile,
        cloudCode: 'permission-denied',
      );

      expect(failure.outcome, WorkspaceMutationOutcome.rejected);
      expect(failure.requiresAuthoritativeRefresh, isFalse);
      expect(failure.message, contains('was not renamed'));
    });

    test('treats an unknown single-record result as uncertain', () {
      final failure = classifyWorkspaceMutationFailure(
        action: WorkspaceMutationAction.createFolder,
      );

      expect(failure.outcome, WorkspaceMutationOutcome.uncertain);
      expect(failure.requiresAuthoritativeRefresh, isTrue);
      expect(failure.message, contains('could not confirm'));
      expect(failure.message, contains('last verified workspace'));
      expect(failure.message, contains('before repeating'));
    });

    test('locks multi-record changes even after a closed cloud rejection', () {
      for (final action in const <WorkspaceMutationAction>[
        WorkspaceMutationAction.moveItems,
        WorkspaceMutationAction.renameFolder,
        WorkspaceMutationAction.removeFolder,
        WorkspaceMutationAction.deleteItems,
      ]) {
        final failure = classifyWorkspaceMutationFailure(
          action: action,
          cloudCode: 'permission-denied',
        );
        expect(
          failure.outcome,
          WorkspaceMutationOutcome.uncertain,
          reason: '$action may have committed an earlier batch',
        );
      }
    });
  });

  group('buildWorkspaceDeleteSelectionPlan', () {
    test('collapses selected descendants and files inside selected trees', () {
      final plan = buildWorkspaceDeleteSelectionPlan(
        folderParentIds: const <String, String?>{
          'parent': null,
          'child': 'parent',
          'grandchild': 'child',
          'other': null,
        },
        selectedFolderIds: const <String>['parent', 'child'],
        selectedFileFolderIds: const <String, String?>{
          'nested-file': 'grandchild',
          'other-file': 'other',
          'root-file': null,
        },
      );

      expect(plan.rootFolderIds, const <String>{'parent'});
      expect(plan.standaloneFileIds, const <String>{'other-file', 'root-file'});
    });

    test('fails safely on malformed folder cycles', () {
      final plan = buildWorkspaceDeleteSelectionPlan(
        folderParentIds: const <String, String?>{'a': 'b', 'b': 'a'},
        selectedFolderIds: const <String>['a'],
        selectedFileFolderIds: const <String, String?>{'file': 'b'},
      );

      expect(plan.rootFolderIds, const <String>{'a'});
      expect(plan.standaloneFileIds, isEmpty);
    });
  });

  testWidgets('uncertain workspace changes expose only a refresh action', (
    tester,
  ) async {
    var refreshes = 0;
    final failure = classifyWorkspaceMutationFailure(
      action: WorkspaceMutationAction.moveItems,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceMutationStatusNotice(
            failure: failure,
            refreshing: false,
            onRefresh: () async {
              refreshes += 1;
            },
          ),
        ),
      ),
    );

    expect(find.textContaining('could not confirm'), findsOneWidget);
    expect(find.text('Refresh files'), findsOneWidget);
    expect(find.textContaining('Try again now'), findsNothing);

    await tester.tap(find.text('Refresh files'));
    await tester.pump();
    expect(refreshes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh control is disabled while authoritative state loads', (
    tester,
  ) async {
    final failure = classifyWorkspaceMutationFailure(
      action: WorkspaceMutationAction.deleteItems,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceMutationStatusNotice(
            failure: failure,
            refreshing: true,
            onRefresh: () async {},
          ),
        ),
      ),
    );

    final button = tester.widget<FilledButton>(
      find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Refreshing files'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  test('workspace mutation boundary excludes raw errors and identifiers', () {
    final source = File(
      'lib/src/home/workspace_home_page.dart',
    ).readAsStringSync();

    expect(source, contains('_ensureWorkspaceMutationReady()'));
    expect(source, contains('WorkspaceMutationStatusNotice('));
    expect(source, contains('GetOptions(source: Source.server)'));
    expect(
      source,
      contains(
        "debugPrint('Authoritative workspace refresh was unavailable.')",
      ),
    );
    expect(
      source,
      isNot(contains("context: 'authoritative workspace refresh'")),
    );
    expect(source, contains('selectedRootFolders'));
    expect(source, contains('standaloneSelectedFiles'));
    expect(source, isNot(contains("debugPrint('Rename failed: \$e')")));
    expect(source, isNot(contains("debugPrint('Move failed: \$e')")));
    expect(source, isNot(contains('Failed to rename folder \${folder.id}')));
    expect(source, isNot(contains('Failed to delete folder \${folder.id}')));
  });
}
