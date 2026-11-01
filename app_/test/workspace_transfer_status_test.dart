import 'package:cloud_storage/src/home/workspace_transfer_controller.dart';
import 'package:cloud_storage/src/home/workspace_transfer_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'progress changes only presentation and cancellation is immediate',
    (tester) async {
      final controller = WorkspaceTransferController();
      addTearDown(controller.dispose);
      var listingBuilds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Builder(
                  builder: (_) {
                    listingBuilds++;
                    return const Text('Files');
                  },
                ),
                WorkspaceTransferStatus(
                  controller: controller,
                  formatBytes: (bytes) => '${bytes.toInt()} B',
                  onCancel: controller.requestCancel,
                ),
              ],
            ),
          ),
        ),
      );
      controller.begin('one', 'Uploading');
      controller.startForegroundUpload(
        id: 'one',
        totalFiles: 1,
        totalBytes: 100,
      );
      await tester.pump();
      for (var i = 1; i <= 100; i++) {
        controller.updateForegroundProgress(transferredBytes: i);
        await tester.pump();
      }
      expect(listingBuilds, 1);
      expect(
        find.text('0/1 finalized, 100 B of 100 B processed'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0.95,
      );
      await tester.tap(find.byTooltip('Cancel remaining uploads'));
      expect(controller.cancelRequested, isTrue);
      await tester.pump();
      expect(find.byTooltip('Cancel remaining uploads'), findsNothing);
      controller.finishForegroundUpload();
      controller.end('one');
      await tester.pump();
      expect(find.text('Transfers in progress'), findsNothing);
      expect(listingBuilds, 1);
    },
  );
}
