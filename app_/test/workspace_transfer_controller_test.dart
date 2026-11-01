import 'package:cloud_storage/src/home/workspace_transfer_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('identical normalized updates reuse the snapshot and stay silent', () {
    final controller = WorkspaceTransferController();
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.begin('one', 'Uploading');
    final original = controller.snapshot;
    controller.begin('one', 'Uploading');
    controller.update('one', 'Uploading');
    controller.update('missing', 'Ignored');
    expect(notifications, 1);
    expect(identical(original, controller.snapshot), isTrue);
    controller.startForegroundUpload(id: 'one', totalFiles: 1, totalBytes: 100);
    controller.updateForegroundProgress(transferredBytes: 100);
    final completeBytes = controller.snapshot;
    final before = notifications;
    controller.updateForegroundProgress(transferredBytes: 101);
    controller.updateForegroundProgress();
    expect(notifications, before);
    expect(identical(completeBytes, controller.snapshot), isTrue);
    controller.update('one', 'Finalizing');
    expect(original.messages, ['Uploading']);
    expect(controller.snapshot.messages, ['Finalizing']);
  });

  test('foreground progress is clamped and reset atomically', () {
    final controller = WorkspaceTransferController();
    addTearDown(controller.dispose);

    controller.startForegroundUpload(
      id: 'upload-1',
      totalFiles: 2,
      totalBytes: 100,
    );
    controller.updateForegroundProgress(
      completedFiles: 99,
      transferredBytes: 150,
    );

    expect(controller.snapshot.completedFiles, 2);
    expect(controller.snapshot.transferredBytes, 100);
    expect(controller.snapshot.progress, 1);

    controller.requestCancel();
    expect(controller.cancelRequested, isTrue);
    controller.finishForegroundUpload();
    expect(controller.snapshot.hasForegroundUpload, isFalse);
    expect(controller.cancelRequested, isFalse);
  });

  test('full byte transfer leaves visible progress for finalization', () {
    final controller = WorkspaceTransferController();
    addTearDown(controller.dispose);

    controller.startForegroundUpload(
      id: 'image-upload',
      totalFiles: 1,
      totalBytes: 100,
    );
    controller.updateForegroundProgress(transferredBytes: 100);

    expect(controller.snapshot.progress, closeTo(0.95, 0.0001));
    expect(controller.snapshot.completedFiles, 0);

    controller.updateForegroundProgress(completedFiles: 1);
    expect(controller.snapshot.progress, 1);
  });

  test('transfer messages cannot be mutated through a snapshot', () {
    final controller = WorkspaceTransferController();
    addTearDown(controller.dispose);
    controller.begin('one', 'Uploading one');

    expect(
      () => controller.snapshot.messages.add('external mutation'),
      throwsUnsupportedError,
    );
  });

  test('one upload intent covers picker, unlock, and transfer preflight', () {
    final controller = WorkspaceTransferController();
    addTearDown(controller.dispose);

    expect(controller.tryStartUploadIntent(), isTrue);
    expect(controller.snapshot.uploadIntentActive, isTrue);
    expect(controller.tryStartUploadIntent(), isFalse);

    controller.startForegroundUpload(
      id: 'upload-after-unlock',
      totalFiles: 1,
      totalBytes: 10,
    );
    controller.finishForegroundUpload();
    expect(controller.tryStartUploadIntent(), isFalse);

    controller.finishUploadIntent();
    expect(controller.snapshot.uploadIntentActive, isFalse);
    expect(controller.tryStartUploadIntent(), isTrue);
  });

  test('active transfer blocks an unreserved competing upload intent', () {
    final controller = WorkspaceTransferController();
    addTearDown(controller.dispose);

    controller.startForegroundUpload(
      id: 'existing-upload',
      totalFiles: 1,
      totalBytes: 10,
    );

    expect(controller.tryStartUploadIntent(), isFalse);
    expect(controller.snapshot.uploadIntentActive, isFalse);
  });
}
