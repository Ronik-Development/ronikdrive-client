import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

enum MemoryPreviewKind { text, image }

class PreviewUnavailable implements Exception {
  const PreviewUnavailable();
  @override
  String toString() => 'Preview unavailable.';
}

// StreamIterator subscribes lazily. Start before authorization so even a
// rejected request can cancel an already-acquired HTTP response stream.
Future<bool> _beginRead(StreamIterator<List<int>> iterator) {
  final pending = iterator.moveNext();
  // Authorization can throw before awaiting this future. Its transport error
  // must still be observed; awaiting pending below retains normal propagation.
  unawaited(pending.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
  return pending;
}

/// Cancellation is permanent: reopening requires a new authorized session.
class PreviewReadGuard extends ChangeNotifier {
  PreviewReadGuard(this.isAuthorized);
  final bool Function() isAuthorized;
  bool _cancelled = false;
  bool get cancelled => _cancelled;

  void check() {
    var allowed = false;
    try {
      allowed = !_cancelled && isAuthorized();
    } catch (_) {
      /* Unavailable authorization is not permission. */
    }
    if (!allowed) {
      cancel();
      throw const PreviewUnavailable();
    }
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    notifyListeners();
  }

  Stream<List<int>> watch(Stream<List<int>> source) async* {
    final iterator = StreamIterator(
      source.timeout(const Duration(seconds: 30)),
    );
    void stop() => unawaited(iterator.cancel().catchError((Object _) {}));
    addListener(stop);
    try {
      var next = _beginRead(iterator);
      check();
      while (await next) {
        check();
        yield iterator.current;
        next = _beginRead(iterator);
      }
      check();
    } finally {
      removeListener(stop);
      await iterator.cancel();
    }
  }
}

/// Owns copies, so wiping never corrupts a buffer owned by the downloader.
/// The caller must wait for authenticated stream completion before takeBytes.
class SensitiveByteBuffer {
  SensitiveByteBuffer({this.maximumBytes});
  final int? maximumBytes;
  final _chunks = <Uint8List>[];
  int _tailLength = 0;
  int length = 0;
  void add(List<int> chunk) {
    if (maximumBytes != null && length + chunk.length > maximumBytes!) {
      throw const PreviewUnavailable();
    }
    var offset = 0;
    // Fixed-size slabs also bound allocation overhead for tiny/empty chunks.
    while (offset < chunk.length) {
      if (_chunks.isEmpty || _tailLength == _chunks.last.length) {
        _chunks.add(Uint8List(64 * 1024));
        _tailLength = 0;
      }
      final count = (chunk.length - offset).clamp(
        0,
        _chunks.last.length - _tailLength,
      );
      _chunks.last.setRange(_tailLength, _tailLength + count, chunk, offset);
      _tailLength += count;
      offset += count;
    }
    length += chunk.length;
  }

  Uint8List takeBytes() {
    final output = Uint8List(length);
    var offset = 0;
    for (final chunk in _chunks) {
      final count = (length - offset).clamp(0, chunk.length);
      output.setRange(offset, offset + count, chunk);
      offset += count;
    }
    clear();
    return output;
  }

  void clear() {
    for (final chunk in _chunks) {
      chunk.fillRange(0, chunk.length, 0);
    }
    _chunks.clear();
    _tailLength = 0;
    length = 0;
  }
}

/// A decrypting stream may emit bytes before its final MAC check. Only its
/// successful completion authorizes returning the assembled plaintext.
Future<Uint8List> readAuthenticatedBytes(
  Stream<List<int>> source, {
  int? maximumBytes,
  required void Function() checkAccess,
  PreviewReadGuard? guard,
}) async {
  final buffer = SensitiveByteBuffer(maximumBytes: maximumBytes);
  final iterator = StreamIterator(
    guard == null ? source : source.timeout(const Duration(seconds: 30)),
  );
  void stop() => unawaited(iterator.cancel().catchError((Object _) {}));
  guard?.addListener(stop);
  try {
    var next = _beginRead(iterator);
    guard?.check();
    checkAccess();
    while (await next) {
      guard?.check();
      checkAccess();
      buffer.add(iterator.current);
      next = _beginRead(iterator);
    }
    guard?.check();
    checkAccess();
    return buffer.takeBytes();
  } finally {
    buffer.clear();
    guard?.removeListener(stop);
    await iterator.cancel();
  }
}

class MemoryPreviewPolicy {
  static const imageBytes = 20 * 1024 * 1024;
  static const textBytes = 1024 * 1024;
  static int limit(MemoryPreviewKind kind) =>
      kind == MemoryPreviewKind.image ? imageBytes : textBytes;

  /// Plain text only. HTML/XML/SVG source is never inserted into a DOM/viewer.
  /// Bounded rows prevent one enormous paragraph from blocking layout.
  static List<String> textRows(Uint8List bytes) {
    if (bytes.length > textBytes) throw const PreviewUnavailable();
    final text = utf8.decode(bytes, allowMalformed: true);
    final rows = <String>[];
    for (final line in LineSplitter.split(text)) {
      if (rows.length >= 16000) throw const PreviewUnavailable();
      if (line.isEmpty) rows.add('');
      var start = 0;
      while (start < line.length) {
        if (rows.length >= 16000) throw const PreviewUnavailable();
        var end = (start + 2048).clamp(0, line.length);
        if (end < line.length &&
            line.codeUnitAt(end - 1) >= 0xd800 &&
            line.codeUnitAt(end - 1) <= 0xdbff) {
          end--;
        }
        rows.add(line.substring(start, end));
        start = end;
      }
    }
    return rows;
  }
}
