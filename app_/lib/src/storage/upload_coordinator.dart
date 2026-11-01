import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart' as crypto;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../shared/release_runtime_config.dart';
import 'multipart_upload_checkpoint_sink.dart';

String _partDigest(Uint8List bytes) => crypto.sha256.convert(bytes).toString();

Stream<List<int>> _cancelableSource(
  Stream<List<int>> source,
  Future<void> abort,
) {
  late StreamController<List<int>> controller;
  StreamSubscription<List<int>>? subscription;
  var stopped = false;
  controller = StreamController<List<int>>(
    onListen: () {
      subscription = source.listen(
        (chunk) {
          if (!stopped) controller.add(chunk);
        },
        onError: (Object error, StackTrace stack) {
          if (!stopped) controller.addError(error, stack);
        },
        onDone: () {
          if (!stopped) unawaited(controller.close());
        },
      );
      unawaited(
        abort.then((_) {
          if (!stopped && !controller.isClosed) {
            stopped = true;
            controller.addError(const UploadFailure('canceled'));
            unawaited(controller.close());
          }
        }),
      );
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: () async {
      stopped = true;
      await subscription?.cancel();
    },
  );
  return controller.stream;
}

class _DigestResult implements Sink<crypto.Digest> {
  crypto.Digest? value;
  @override
  void add(crypto.Digest data) {
    value = data;
  }

  @override
  void close() {}
}

Future<String> _webPartDigest(Uint8List bytes) async {
  final output = _DigestResult();
  final converter = crypto.sha256.startChunkedConversion(output);
  for (var start = 0; start < bytes.length; start += 64 * 1024) {
    converter.add(
      Uint8List.sublistView(bytes, start, min(bytes.length, start + 64 * 1024)),
    );
    await Future<void>.delayed(Duration.zero);
  }
  converter.close();
  return output.value.toString();
}

enum UploadJobState {
  queued,
  preparing,
  encrypting,
  uploading,
  paused,
  finalizing,
  completed,
  failed,
  canceled,
}

class UploadProgress {
  const UploadProgress({
    required this.acknowledgedBytes,
    required this.totalBytes,
    required this.bytesPerSecond,
  });
  final int acknowledgedBytes;
  final int totalBytes;
  final double bytesPerSecond;
  Duration? get remaining => bytesPerSecond <= 0
      ? null
      : Duration(
          seconds: ((totalBytes - acknowledgedBytes) / bytesPerSecond).ceil(),
        );
}

class UploadJob {
  UploadJob(this.id, this.totalBytes);
  final String id;
  final int totalBytes;
  UploadJobState state = UploadJobState.queued;
  int acknowledgedBytes = 0;
  double bytesPerSecond = 0;
  final Stopwatch clock = Stopwatch()..start();
  Completer<void>? _pause;
  final Completer<void> _abort = Completer<void>();
  Future<void> get abortSignal => _abort.future;
  void abortTransport() {
    if (!_abort.isCompleted) _abort.complete();
  }

  bool canceled = false;
  UploadProgress get progress => UploadProgress(
    acknowledgedBytes: acknowledgedBytes,
    totalBytes: totalBytes,
    bytesPerSecond: bytesPerSecond,
  );
  void pause() {
    if (!const {
      UploadJobState.queued,
      UploadJobState.preparing,
      UploadJobState.encrypting,
      UploadJobState.uploading,
      UploadJobState.paused,
    }.contains(state)) {
      return;
    }
    _pause ??= Completer<void>();
    state = UploadJobState.paused;
  }

  void resume() {
    _pause?.complete();
    _pause = null;
    if (state == UploadJobState.paused) state = UploadJobState.uploading;
  }

  void cancel() {
    if (const {
      UploadJobState.completed,
      UploadJobState.finalizing,
      UploadJobState.failed,
      UploadJobState.canceled,
    }.contains(state)) {
      return;
    }
    canceled = true;
    abortTransport();
    resume();
    state = UploadJobState.canceled;
  }

  Future<void> ready() async {
    await _pause?.future;
    if (canceled) throw const UploadFailure('canceled');
  }
}

class UploadBatch {
  UploadBatch({required this.id, required this.encryptedBytes});
  final String id;
  final int encryptedBytes;
  bool canceled = false;
}

class UploadCapacityDecision implements Exception {
  UploadCapacityDecision(Map<String, dynamic> value)
    : capacityBytes = (value['capacityBytes'] as num?)?.toInt() ?? 0,
      usageBytes = (value['usageBytes'] as num?)?.toInt() ?? 0,
      reservedBytes = (value['reservedBytes'] as num?)?.toInt() ?? 0,
      selectedBytes = (value['selectedBytes'] as num?)?.toInt() ?? 0,
      shortfallBytes = (value['shortfallBytes'] as num?)?.toInt() ?? 0;
  final int capacityBytes,
      usageBytes,
      reservedBytes,
      selectedBytes,
      shortfallBytes;
  int get remainingBytes => max(0, capacityBytes - usageBytes - reservedBytes);
  @override
  String toString() => 'UploadCapacityDecision: quota_exceeded';
}

class UploadFailure implements Exception {
  const UploadFailure(this.code);
  final String code;
  @override
  String toString() => 'UploadFailure';
}

/// One pool shared by every upload producer, including background backups.
/// A permit is acquired before reading a part, bounding encryption buffering.
class UploadScheduler {
  UploadScheduler({required this.mobile}) : limit = mobile ? 2 : 4;
  final bool mobile;
  int limit;
  int _active = 0;
  int _successes = 0;
  bool _restricted = false;
  final Queue<({Completer<void> completion, int bytes})> _waiters = Queue();
  int bufferedBytes = 0;
  int get bufferLimit => (mobile ? 32 : 64) * 1024 * 1024;
  int get active => _active;
  int get maxSlots => mobile ? 3 : 6;
  void setRestricted(bool value) {
    _restricted = value;
    limit = value ? 1 : (mobile ? 2 : 4);
    _drain();
  }

  Future<void> acquire({int bytes = 0}) {
    if (bytes < 0 || bytes > bufferLimit) {
      throw ArgumentError('Invalid upload buffer size');
    }
    final waiter = Completer<void>();
    _waiters.add((completion: waiter, bytes: bytes));
    _drain();
    return waiter.future;
  }

  void _drain() {
    while (_active < limit && _waiters.isNotEmpty) {
      if (bufferedBytes + _waiters.first.bytes > bufferLimit) return;
      final waiter = _waiters.removeFirst();
      _active++;
      bufferedBytes += waiter.bytes;
      waiter.completion.complete();
    }
  }

  void release({bool success = true, int bytes = 0}) {
    if (_active <= 0) throw StateError('Unbalanced upload permit');
    if (bytes < 0 || bytes > bufferedBytes) {
      throw StateError('Unbalanced upload buffer');
    }
    _active--;
    bufferedBytes -= bytes;
    if (!success) {
      _successes = 0;
      limit = max(_restricted || mobile ? 1 : 2, limit - 1);
    } else if (++_successes >= 16 && !_restricted) {
      limit = min(maxSlots, limit + 1);
      _successes = 0;
    }
    _drain();
  }
}

class UploadPreparationGate {
  Future<void> _tail = Future<void>.value();
  Future<void Function()> acquire() async {
    final previous = _tail;
    final next = Completer<void>();
    _tail = next.future;
    await previous;
    return () {
      if (!next.isCompleted) next.complete();
    };
  }
}

class UploadSessionApi {
  UploadSessionApi({
    required this.client,
    required this.tokenProvider,
    Uri? baseUri,
  }) : baseUri = baseUri ?? ReleaseRuntimeConfig.resolveCheckoutApiBaseUri();
  final http.Client client;
  final Future<String?> Function() tokenProvider;
  final Uri baseUri;
  Future<Map<String, dynamic>> call(
    String operation,
    Map<String, dynamic> body,
  ) async {
    final token = await tokenProvider();
    if (token == null || token.isEmpty) {
      throw const UploadFailure('unauthorized');
    }
    final response = await client
        .post(
          baseUri.resolve('storage/uploads/$operation'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            ...body,
            'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
          }),
        )
        .timeout(const Duration(seconds: 45));
    Map<String, dynamic> data = {};
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      /* fixed failure below */
    }
    if (response.statusCode == 409 && data['code'] == 'quota_exceeded') {
      throw UploadCapacityDecision(data);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw UploadFailure(switch (response.statusCode) {
        401 || 403 => 'unauthorized',
        404 when data['code'] == 'upload_unavailable' => 'not_found',
        409 when data['code'] == 'incomplete_upload' => 'incomplete_upload',
        410 => 'expired',
        429 => 'rate_limited',
        _ => 'unavailable',
      });
    }
    return data;
  }
}

class UploadCoordinator extends ChangeNotifier {
  UploadCoordinator({UploadScheduler? scheduler})
    : scheduler =
          scheduler ??
          UploadScheduler(
            mobile:
                !kIsWeb &&
                (defaultTargetPlatform == TargetPlatform.iOS ||
                    defaultTargetPlatform == TargetPlatform.android),
          );
  static final UploadCoordinator instance = UploadCoordinator();
  static const enabled = bool.fromEnvironment(
    'RESUMABLE_UPLOADS',
    defaultValue: false,
  );
  static const partBytes = 8 * 1024 * 1024;
  static final Object _batchZoneKey = Object();
  static final Object _batchControlZoneKey = Object();
  final UploadScheduler scheduler;
  final Map<String, UploadJob> _jobs = {};
  final Map<String, String> _objectJobs = {};
  final Set<UploadBatch> _batches = {};
  bool _paused = false;
  String? _accountUid;
  void bindAccount(String? uid) {
    if (_accountUid == uid) return;
    cancelAll();
    _jobs.clear();
    _objectJobs.clear();
    _accountUid = uid;
    notifyListeners();
  }

  List<UploadJob> get jobs => List.unmodifiable(_jobs.values);
  String? get currentBatchId => Zone.current[_batchZoneKey] as String?;
  String newId() => List.generate(
    24,
    (_) => Random.secure().nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  Future<T> inBatch<T>(String batchId, Future<T> Function() action) async {
    final batch = UploadBatch(id: batchId, encryptedBytes: 0);
    _batches.add(batch);
    try {
      return await runZoned(
        action,
        zoneValues: {_batchZoneKey: batchId, _batchControlZoneKey: batch},
      );
    } finally {
      _batches.remove(batch);
    }
  }

  Future<T> withoutBatch<T>(Future<T> Function() action) =>
      runZoned(action, zoneValues: {_batchZoneKey: null});
  Future<T> prepareBatch<T>({
    List<String> resumeSessionIds = const [],
    required int encryptedBytes,
    required UploadSessionApi api,
    required Future<T> Function() action,
  }) async {
    if (!enabled || currentBatchId != null || encryptedBytes == 0) {
      return action();
    }
    final id = newId();
    await api.call('prepare', {
      'batchId': id,
      'encryptedBytes': encryptedBytes,
      if (resumeSessionIds.isNotEmpty) 'resumeSessionIds': resumeSessionIds,
    });
    try {
      return await inBatch(id, action);
    } finally {
      try {
        await api.call('releaseBatch', {'batchId': id});
      } catch (_) {
        /* Expiry releases unused capacity if offline. */
      }
    }
  }

  void pauseAll() {
    _paused = true;
    for (final job in _jobs.values) {
      job.pause();
    }
    notifyListeners();
  }

  void resumeAll() {
    _paused = false;
    for (final job in _jobs.values) {
      job.resume();
    }
    notifyListeners();
  }

  void cancelAll() {
    _paused = false;
    for (final batch in _batches) {
      batch.canceled = true;
    }
    for (final job in _jobs.values) {
      job.cancel();
    }
    notifyListeners();
  }

  void metadataCompleted(String objectKey) {
    final keys = _objectJobs.keys
        .where((key) => key == objectKey || key.startsWith('$objectKey.parts/'))
        .toList();
    for (final key in keys) {
      final job = _jobs[_objectJobs.remove(key)];
      if (job != null) job.state = UploadJobState.completed;
    }
    if (keys.isNotEmpty) notifyListeners();
  }

  void metadataDeferred(String objectKey) {
    final keys = _objectJobs.keys
        .where((key) => key == objectKey || key.startsWith('$objectKey.parts/'))
        .toList();
    for (final key in keys) {
      final job = _jobs[_objectJobs[key]];
      if (job != null) job.state = UploadJobState.failed;
    }
    if (keys.isNotEmpty) notifyListeners();
  }

  Future<void> upload({
    required String objectKey,
    required int length,
    required Stream<List<int>> ciphertext,
    required UploadSessionApi api,
    required Future<void> Function(Uri, Uint8List) put,
    Future<String?> Function(Uri, Uint8List)? putWithETag,
    Future<String?> Function(Uri, Uint8List, Future<void>, Map<String, String>)?
    putCancellable,
    void Function(int)? onAcknowledged,
    String? transferId,
    ResumableUploadCheckpointSink? checkpointSink,
    bool awaitMetadata = false,
  }) async {
    if ((Zone.current[_batchControlZoneKey] as UploadBatch?)?.canceled ==
        true) {
      throw const UploadFailure('canceled');
    }
    final job = UploadJob(newId(), length);
    if (_jobs.length >= 100) {
      final terminal = _jobs.values
          .where(
            (entry) => const {
              UploadJobState.completed,
              UploadJobState.canceled,
            }.contains(entry.state),
          )
          .map((entry) => entry.id)
          .toList();
      for (final id in terminal) {
        _jobs.remove(id);
      }
    }
    _jobs[job.id] = job;
    if (awaitMetadata) _objectJobs[objectKey] = job.id;
    job.state = UploadJobState.preparing;
    if (_paused) job.pause();
    notifyListeners();
    String? sessionId;
    Object? failure;
    final pending = <Future<void>>[];
    try {
      final session = await api.call('start', {
        'objectKey': objectKey,
        'encryptedBytes': length,
        if (currentBatchId != null) 'batchId': currentBatchId,
      });
      sessionId = session['sessionId'] as String;
      final checkpoint = transferId == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(
              checkpointSink?.uploadCheckpoint(transferId) ?? {},
            );
      final savedParts = Map<String, dynamic>.from(
        checkpoint['parts'] as Map? ?? {},
      );
      final savedETags = Map<String, dynamic>.from(
        checkpoint['eTags'] as Map? ?? {},
      );
      checkpoint.addAll({
        'sessionId': sessionId,
        'encryptedBytes': length,
        'partBytes': partBytes,
        'batchId': currentBatchId,
        'parts': savedParts,
        'eTags': savedETags,
      });
      Future<void> save() async {
        if (transferId != null && checkpointSink != null) {
          await checkpointSink.saveUploadCheckpoint(transferId, checkpoint);
        }
      }

      await save();
      final remote = await api.call('status', {'sessionId': sessionId});
      final uploaded = remote['status'] == 'uploaded';
      final remoteParts = <int, Map>{
        for (final part in remote['parts'] as List? ?? const [])
          (part as Map)['partNumber'] as int: part,
      };
      final iterator = StreamIterator<List<int>>(
        _cancelableSource(ciphertext, job.abortSignal),
      );
      List<int> source = const [];
      var offset = 0;
      var sent = 0;
      var part = 1;
      try {
        while (sent < length) {
          await job.ready();
          final count = min(partBytes, length - sent);
          // Account for the live part plus one transport/hash working copy.
          final memoryCharge = 2 * count;
          await scheduler.acquire(bytes: memoryCharge);
          var delegated = false;
          try {
            if (failure != null) throw failure!;
            await job.ready();
            final buffer = Uint8List(count);
            var filled = 0;
            while (filled < count) {
              if (offset == source.length) {
                if (!await iterator.moveNext()) {
                  throw const UploadFailure('source_changed');
                }
                source = iterator.current;
                offset = 0;
              }
              final take = min(count - filled, source.length - offset);
              buffer.setRange(filled, filled + take, source, offset);
              offset += take;
              filled += take;
            }
            final number = part++;
            final digest = kIsWeb
                ? await _webPartDigest(buffer)
                : await compute(_partDigest, buffer);
            if (savedParts.containsKey('$number') &&
                savedParts['$number'] != digest) {
              throw const UploadFailure('source_changed');
            }
            sent += count;
            job.state = UploadJobState.uploading;
            final task = () async {
              var success = false;
              try {
                if (savedParts['$number'] == digest &&
                    (uploaded ||
                        remoteParts[number]?['length'] == count &&
                            savedETags['$number'] != null &&
                            remoteParts[number]?['eTag'] ==
                                savedETags['$number'])) {
                  success = true;
                  job.acknowledgedBytes += count;
                  onAcknowledged?.call(job.acknowledgedBytes);
                  notifyListeners();
                  return;
                }
                if (uploaded) throw const UploadFailure('source_changed');
                for (var attempt = 0; attempt < 4; attempt++) {
                  await job.ready();
                  try {
                    final auth = await api.call('urls', {
                      'sessionId': sessionId,
                      'partNumbers': [number],
                    });
                    final signed = (auth['parts'] as List).single as Map;
                    final url = Uri.parse(signed['url'] as String);
                    final headers = Map<String, String>.from(
                      signed['headers'] as Map? ?? {},
                    );
                    if (headers.keys.any(
                          (key) => key != 'x-amz-meta-upload-session',
                        ) ||
                        headers.values.any((value) => value != sessionId)) {
                      throw const UploadFailure('unauthorized');
                    }
                    if (headers.isNotEmpty && putCancellable == null) {
                      throw const UploadFailure('unavailable');
                    }
                    await job.ready();
                    if (putCancellable != null) {
                      final eTag = await putCancellable(
                        url,
                        buffer,
                        job.abortSignal,
                        headers,
                      );
                      if (eTag != null) savedETags['$number'] = eTag;
                    } else if (putWithETag != null) {
                      final eTag = await putWithETag(url, buffer);
                      if (eTag != null) savedETags['$number'] = eTag;
                    } else {
                      await put(url, buffer);
                    }
                    await job.ready();
                    savedParts['$number'] = digest;
                    await save();
                    success = true;
                    job.acknowledgedBytes += count;
                    final seconds = job.clock.elapsedMilliseconds / 1000;
                    if (seconds > 0) {
                      job.bytesPerSecond = job.acknowledgedBytes / seconds;
                    }
                    onAcknowledged?.call(job.acknowledgedBytes);
                    notifyListeners();
                    return;
                  } on UploadCapacityDecision {
                    rethrow;
                  } catch (error) {
                    if (attempt == 3 ||
                        error is UploadFailure &&
                            [
                              'unauthorized',
                              'expired',
                              'canceled',
                            ].contains(error.code)) {
                      rethrow;
                    }
                    checkpoint['retryCount'] =
                        (checkpoint['retryCount'] as int? ?? 0) + 1;
                    await save();
                    await Future<void>.delayed(
                      Duration(
                        milliseconds:
                            500 * (1 << attempt) + Random().nextInt(250),
                      ),
                    );
                  }
                }
              } catch (error) {
                failure ??= error;
                job.abortTransport();
                job.resume();
              } finally {
                scheduler.release(success: success, bytes: memoryCharge);
              }
            }();
            pending.add(task);
            delegated = true;
          } finally {
            if (!delegated) {
              scheduler.release(success: false, bytes: memoryCharge);
            }
          }
        }
        if (offset != source.length || await iterator.moveNext()) {
          throw const UploadFailure('source_changed');
        }
      } finally {
        await iterator.cancel();
      }
      await Future.wait(pending);
      if (failure != null) throw failure!;
      await job.ready();
      job.state = UploadJobState.finalizing;
      notifyListeners();
      await api.call('complete', {'sessionId': sessionId});
      if (!awaitMetadata) job.state = UploadJobState.completed;
    } catch (_) {
      job.abortTransport();
      job.resume();
      await Future.wait(pending);
      job.state = job.canceled
          ? UploadJobState.canceled
          : UploadJobState.failed;
      if (job.canceled && sessionId != null) {
        try {
          await api.call('abort', {'sessionId': sessionId});
        } catch (_) {
          /* server cleanup retries */
        }
      }
      if (job.canceled) throw const UploadFailure('canceled');
      rethrow;
    } finally {
      job.abortTransport();
      notifyListeners();
    }
  }
}
