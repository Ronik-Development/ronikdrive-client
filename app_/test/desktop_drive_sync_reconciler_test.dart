import 'package:cloud_storage/src/desktop_drive/sync_reconciler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const absent = DriveObservation.absent();
  const unknown = DriveObservation.unknown();
  const local = DriveObservation.present('local-1');
  const remote = DriveObservation.present('remote-1');
  const editedLocal = DriveObservation.present('local-2');
  const editedRemote = DriveObservation.present('remote-2');
  final baseline = DriveSyncBaseline(local: local, remote: remote);

  DriveSyncDecision decide(
    DriveObservation l,
    DriveObservation r, {
    bool ready = true,
    bool firstContact = false,
  }) => reconcileDriveItem(
    local: l,
    remote: r,
    baseline: firstContact ? null : baseline,
    accountReady: ready,
  );

  test('unchanged items need no transfer', () {
    expect(decide(local, remote).action, DriveSyncAction.none);
  });
  test('local and remote edits transfer in the correct direction', () {
    expect(decide(editedLocal, remote).action, DriveSyncAction.upload);
    expect(decide(local, editedRemote).action, DriveSyncAction.download);
  });
  test('acknowledged deletions recycle the unchanged counterpart', () {
    expect(decide(absent, remote).action, DriveSyncAction.recycleRemote);
    expect(decide(local, absent).action, DriveSyncAction.recycleLocal);
    expect(decide(absent, absent).action, DriveSyncAction.none);
  });
  test('concurrent edits and edit/delete races preserve work', () {
    for (final pair in [
      (editedLocal, editedRemote),
      (editedLocal, absent),
      (absent, editedRemote),
    ]) {
      expect(decide(pair.$1, pair.$2).action, DriveSyncAction.preserveConflict);
    }
  });
  test('first contact never interprets absence as a deletion', () {
    expect(
      decide(absent, remote, firstContact: true).action,
      DriveSyncAction.download,
    );
    expect(
      decide(local, absent, firstContact: true).action,
      DriveSyncAction.upload,
    );
    expect(
      decide(local, local, firstContact: true).action,
      DriveSyncAction.preserveConflict,
    );
  });
  test('unknown observations and locked accounts cannot mutate files', () {
    for (final l in [absent, unknown, local, editedLocal]) {
      for (final r in [absent, unknown, remote, editedRemote]) {
        expect(decide(l, r, ready: false).action, DriveSyncAction.defer);
        if (!l.isKnown || !r.isKnown) {
          expect(decide(l, r).action, DriveSyncAction.defer);
        }
      }
    }
  });
  test('a stale decision cannot overwrite an edit made after the scan', () {
    final upload = decide(editedLocal, remote);
    expect(
      upload.stillApplies(currentLocal: editedLocal, currentRemote: remote),
      isTrue,
    );
    expect(
      upload.stillApplies(
        currentLocal: editedLocal,
        currentRemote: editedRemote,
      ),
      isFalse,
    );
    expect(
      upload.stillApplies(currentLocal: local, currentRemote: remote),
      isFalse,
    );
    expect(
      upload.stillApplies(currentLocal: editedLocal, currentRemote: unknown),
      isFalse,
    );
  });
  test('an item recreated after acknowledged deletion is uploaded', () {
    expect(
      reconcileDriveItem(
        local: editedLocal,
        remote: absent,
        accountReady: true,
        baseline: DriveSyncBaseline(local: absent, remote: absent),
      ).action,
      DriveSyncAction.upload,
    );
  });
  test('invalid baselines and empty revisions fail closed', () {
    expect(
      () => DriveSyncBaseline(local: unknown, remote: remote),
      throwsArgumentError,
    );
    expect(
      () => DriveSyncBaseline(local: local, remote: absent),
      throwsArgumentError,
    );
    expect(
      () => decide(const DriveObservation.present(''), remote),
      throwsArgumentError,
    );
  });
}
