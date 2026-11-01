import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'windows_upload_hash.dart';

/// One worker per pass, with only one block in flight. Downstream backpressure
/// prevents prefetching plaintext; cancellation and errors dispose the worker.
Stream<(Uint8List, String)> hashUploadBlocks(Stream<Uint8List> blocks) async* {
  final replies = ReceivePort();
  final messages = StreamIterator<dynamic>(replies);
  Isolate? worker;
  try {
    worker = await Isolate.spawn(
      _hashWorker,
      replies.sendPort,
      onError: replies.sendPort,
      onExit: replies.sendPort,
    );
    if (!await messages.moveNext() || messages.current is! SendPort) {
      throw StateError('Upload fingerprint worker interrupted');
    }
    final requests = messages.current as SendPort;
    await for (final block in blocks) {
      requests.send(block);
      if (!await messages.moveNext() || messages.current is! String) {
        throw StateError('Upload fingerprint worker interrupted');
      }
      yield (block, messages.current as String);
    }
  } finally {
    // Allow the current bounded synchronous hash to wipe/free native buffers.
    worker?.kill(priority: Isolate.beforeNextEvent);
    replies.close();
    await messages.cancel();
  }
}

void _hashWorker(SendPort replies) {
  final requests = ReceivePort();
  replies.send(requests.sendPort);
  requests.listen((dynamic block) {
    final bytes = block as Uint8List;
    replies.send(
      WindowsUploadHash.instance?.digest(bytes) ??
          sha256.convert(bytes).toString(),
    );
  });
}
