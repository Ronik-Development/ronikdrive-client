/// Side-effect-free reconciliation shared by the Windows and macOS providers.
///
/// A revision covers content AND metadata (including parent/name). Revisions
/// are opaque and only comparable within one replica. Never use timestamps as
/// revisions or compare a local revision with a server revision.
class DriveObservation {
  const DriveObservation.present(String this.revision)
    : kind = DriveObservationKind.present;
  const DriveObservation.absent()
    : kind = DriveObservationKind.absent,
      revision = null;
  const DriveObservation.unknown()
    : kind = DriveObservationKind.unknown,
      revision = null;

  final DriveObservationKind kind;
  final String? revision;

  bool get isKnown => kind != DriveObservationKind.unknown;
  bool get isPresent => kind == DriveObservationKind.present;
}

enum DriveObservationKind { present, absent, unknown }

/// The two observations acknowledged AFTER the last successful operation.
/// Persist this inside the account/environment-scoped encrypted private cache.
/// A null baseline means first contact, never proof of deletion.
class DriveSyncBaseline {
  DriveSyncBaseline({required this.local, required this.remote}) {
    if (!local.isKnown ||
        !remote.isKnown ||
        local.isPresent != remote.isPresent) {
      throw ArgumentError('A baseline must describe acknowledged replicas.');
    }
    _validate(local);
    _validate(remote);
  }

  final DriveObservation local;
  final DriveObservation remote;
}

enum DriveSyncAction {
  /// Incomplete enumeration, expired authorization, or locked encryption key.
  defer,
  none,
  upload,
  download,

  /// Recycle, never permanently delete, after validating both preconditions.
  recycleLocal,
  recycleRemote,

  /// Keep both versions until a durable conflict copy has been acknowledged.
  preserveConflict,
}

class DriveSyncDecision {
  const DriveSyncDecision._(this.action, this.local, this.remote);

  final DriveSyncAction action;

  /// Preconditions to recheck immediately before executing the operation.
  final DriveObservation local;
  final DriveObservation remote;

  bool stillApplies({
    required DriveObservation currentLocal,
    required DriveObservation currentRemote,
  }) =>
      action != DriveSyncAction.defer &&
      _same(local, currentLocal) &&
      _same(remote, currentRemote);
}

/// Reconcile one stable item ID, not one path. A rename changes its revision;
/// an unhydrated placeholder remains present. `absent` requires an authoritative
/// lookup, a completed listing, or an explicit deletion event. Network errors,
/// denied access, locked keys and unfinished pages MUST be `unknown`.
DriveSyncDecision reconcileDriveItem({
  required DriveObservation local,
  required DriveObservation remote,
  DriveSyncBaseline? baseline,
  required bool accountReady,
}) {
  _validate(local);
  _validate(remote);
  DriveSyncDecision result(DriveSyncAction action) =>
      DriveSyncDecision._(action, local, remote);

  if (!accountReady || !local.isKnown || !remote.isKnown) {
    return result(DriveSyncAction.defer);
  }
  if (!local.isPresent && !remote.isPresent) {
    return result(DriveSyncAction.none);
  }

  if (baseline == null) {
    if (local.isPresent && remote.isPresent) {
      // Equal-looking revision strings across replicas do not prove equality.
      return result(DriveSyncAction.preserveConflict);
    }
    return result(
      local.isPresent ? DriveSyncAction.upload : DriveSyncAction.download,
    );
  }

  final localChanged = !_same(local, baseline.local);
  final remoteChanged = !_same(remote, baseline.remote);
  if (!localChanged && !remoteChanged) {
    return result(DriveSyncAction.none);
  }
  if (localChanged && remoteChanged) {
    // Includes edit-vs-delete and divergent rename-vs-edit races.
    return result(DriveSyncAction.preserveConflict);
  }
  if (localChanged) {
    return result(
      local.isPresent ? DriveSyncAction.upload : DriveSyncAction.recycleRemote,
    );
  }
  return result(
    remote.isPresent ? DriveSyncAction.download : DriveSyncAction.recycleLocal,
  );
}

bool _same(DriveObservation a, DriveObservation b) =>
    a.isKnown && b.isKnown && a.kind == b.kind && a.revision == b.revision;

void _validate(DriveObservation observation) {
  if (observation.isPresent &&
      (observation.revision == null || observation.revision!.isEmpty)) {
    throw ArgumentError('A present item requires an opaque revision.');
  }
}
