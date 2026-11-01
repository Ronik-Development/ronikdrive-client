part of 'native_firestore_rpc.dart';

/// One live target with checkpoints: partial batches are never published or
/// resumed as complete snapshots. Cancellation releases its RPC and listeners.
class _NativeFirestoreWatch {
  _NativeFirestoreWatch(this._rpc, rpc.Target target)
    : _target = (rpc.Target.fromBuffer(target.writeToBuffer())
        ..targetId = 1
        ..clearResumeToken()
        ..clearReadTime()) {
    _updates = StreamController<List<wire.Document>>(
      onListen: _start,
      onCancel: _stop,
      onPause: () {
        _paused = true;
        _subscription?.pause();
      },
      onResume: () {
        _paused = false;
        _subscription?.resume();
      },
    );
  }
  final NativeFirestoreRpc _rpc;
  final rpc.Target _target;
  late final String? _uid;
  late final StreamController<List<wire.Document>> _updates;
  final _working = <String, wire.Document>{};
  Map<String, wire.Document> _committed = {};
  List<int> _resume = [];
  StreamController<rpc.ListenRequest>? _requests;
  grpc.ResponseStream<rpc.ListenResponse>? _call;
  StreamSubscription<rpc.ListenResponse>? _subscription;
  StreamSubscription<NativeAuthIdentity?>? _auth;
  Timer? _retry;
  int _epoch = 0;
  int _failures = 0;
  bool _closed = false;
  bool _current = false;
  bool _published = false;
  bool _dirty = false;
  bool _paused = false;

  Stream<List<wire.Document>> get stream => _updates.stream.map((documents) {
    if (_uid != _rpc.session.currentIdentity?.uid) {
      throw NativeFirestoreRpc._error('cancelled');
    }
    return documents;
  });
  bool _valid(int epoch) => !_closed && epoch == _epoch;

  void _start() {
    _uid = _rpc.session.currentIdentity?.uid;
    if (_rpc._closed) {
      _fail(NativeFirestoreRpc._error('failed-precondition'));
      return;
    }
    _rpc._watches.add(this);
    if (_uid != _rpc.session.currentIdentity?.uid) {
      _fail(NativeFirestoreRpc._error('cancelled'));
      return;
    }
    _auth = _rpc.session.changes.listen((identity) {
      if (identity?.uid != _uid) {
        _fail(NativeFirestoreRpc._error('cancelled'));
      } else {
        unawaited(_restart());
      }
    });
    _open();
  }

  void _open() {
    if (_closed) return;
    final epoch = ++_epoch;
    final target = rpc.Target.fromBuffer(_target.writeToBuffer());
    if (_resume.isNotEmpty) target.resumeToken = _resume;
    _requests = StreamController<rpc.ListenRequest>();
    _call = _rpc._client.listen(
      _requests!.stream,
      options: _rpc._options(_uid),
    );
    _subscription = _call!.listen(
      (response) {
        if (_valid(epoch)) _handle(response);
      },
      onError: (Object error) {
        if (_valid(epoch)) _lost(error is grpc.GrpcError ? error.code : 14);
      },
      onDone: () {
        if (_valid(epoch)) _lost(14);
      },
    );
    if (_paused) _subscription!.pause();
    _requests!.add(
      rpc.ListenRequest(database: _rpc.database, addTarget: target),
    );
  }

  void _handle(rpc.ListenResponse response) {
    if (response.hasDocumentChange()) {
      final change = response.documentChange;
      if (change.removedTargetIds.contains(1)) {
        _dirty = _working.remove(change.document.name) != null || _dirty;
      }
      if (change.targetIds.contains(1)) {
        final document = change.document;
        if (!document.name.startsWith('${_rpc.documentsRoot}/')) {
          _fail(NativeFirestoreRpc._error('data-loss'));
          return;
        }
        document.freeze();
        _working[document.name] = document;
        _dirty = true;
      }
    }
    if (response.hasDocumentDelete()) {
      _dirty =
          _working.remove(response.documentDelete.document) != null || _dirty;
    }
    if (response.hasDocumentRemove()) {
      _dirty =
          _working.remove(response.documentRemove.document) != null || _dirty;
    }
    if (response.hasFilter() &&
        response.filter.targetId == 1 &&
        response.filter.count != _working.length) {
      unawaited(_restart(reset: true));
      return;
    }
    if (!response.hasTargetChange()) return;
    final change = response.targetChange;
    if (change.targetIds.isNotEmpty && !change.targetIds.contains(1)) return;
    switch (change.targetChangeType) {
      case rpc.TargetChange_TargetChangeType.REMOVE:
        _lost(
          change.hasCause() && change.cause.code != 0 ? change.cause.code : 14,
        );
        return;
      case rpc.TargetChange_TargetChangeType.RESET:
        _working.clear();
        _committed.clear();
        _resume = [];
        _current = false;
        _published = false;
        _dirty = true;
      case rpc.TargetChange_TargetChangeType.CURRENT:
        _current = true;
      default:
        break;
    }
    if (!_current || !change.hasReadTime()) return;
    _committed = Map.from(_working);
    if (change.resumeToken.isNotEmpty) _resume = List.of(change.resumeToken);
    _failures = 0;
    if (_dirty || !_published) {
      _published = true;
      _dirty = false;
      if (_uid != _rpc.session.currentIdentity?.uid) {
        _fail(NativeFirestoreRpc._error('cancelled'));
        return;
      }
      _updates.add(List.unmodifiable(_committed.values));
    }
  }

  void _lost(int code) {
    if (_closed) return;
    if (!const {1, 4, 8, 13, 14}.contains(code)) {
      _fail(NativeFirestoreRpc._grpcError(code));
      return;
    }
    ++_epoch;
    _working
      ..clear()
      ..addAll(_committed);
    _dirty = false;
    final seconds = _failures >= 6 ? 60 : 1 << _failures;
    _failures++;
    _retry?.cancel();
    _retry = Timer(Duration(seconds: seconds), () {
      unawaited(_restart());
    });
  }

  Future<void> _disconnect() async {
    final call = _call;
    _call = null;
    final subscription = _subscription;
    _subscription = null;
    final requests = _requests;
    _requests = null;
    if (call != null) await call.cancel();
    await subscription?.cancel();
    if (requests != null) unawaited(requests.close());
  }

  Future<void> _restart({bool reset = false}) async {
    if (_closed) return;
    final epoch = ++_epoch;
    _retry?.cancel();
    await _disconnect();
    if (!_valid(epoch)) return;
    if (reset || _resume.isEmpty) {
      _resume = [];
      _committed.clear();
      _current = false;
      _published = false;
    }
    _working
      ..clear()
      ..addAll(_committed);
    _dirty = false;
    _open();
  }

  void _fail(FirebaseException error) {
    if (_closed) return;
    _updates.addError(error);
    unawaited(close());
  }

  Future<void> _stop() async {
    if (_closed) return;
    _closed = true;
    ++_epoch;
    _retry?.cancel();
    await _auth?.cancel();
    await _disconnect();
    _working.clear();
    _committed.clear();
    _resume = [];
    _rpc._watches.remove(this);
  }

  Future<void> close() async {
    await _stop();
    // A paused consumer must not keep the app or its RPC channel alive.
    unawaited(_updates.close());
  }
}
