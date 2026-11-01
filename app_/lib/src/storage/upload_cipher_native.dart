import 'dart:async';
import 'dart:isolate';
import 'package:cryptography/cryptography.dart';
import 'upload_chunks.dart';

/// Input is pulled only when the worker requests it. Output is acknowledged
/// only after the downstream consumer resumes, so both channels are bounded.
Stream<List<int>> encryptUploadStream(
  Stream<List<int>> input,
  SecretKey key,
  List<int> nonce,
) async* {
  final events = ReceivePort();
  final source = StreamIterator<List<int>>(boundedUploadChunks(input));
  Isolate? worker;
  SendPort? inputPort;
  SendPort? acknowledgment;
  try {
    worker = await Isolate.spawn(
      _encryptWorker,
      [events.sendPort, await key.extractBytes(), nonce],
      onError: events.sendPort,
      onExit: events.sendPort,
    );
    await for (final event in events) {
      if (event is! List || event.isEmpty) {
        throw StateError('Upload encryption interrupted');
      }
      switch (event.first) {
        case 'ready':
          inputPort = event[1] as SendPort;
          acknowledgment = event[2] as SendPort;
        case 'input':
          inputPort!.send(await source.moveNext() ? source.current : null);
        case 'data':
          yield event[1] as List<int>;
          acknowledgment!.send(true);
        case 'done':
          return;
        default:
          throw StateError('Upload encryption interrupted');
      }
    }
  } finally {
    worker?.kill(priority: Isolate.immediate);
    events.close();
    await source.cancel();
  }
}

Future<void> _encryptWorker(List<Object> initialization) async {
  final output = initialization[0] as SendPort;
  final inputPort = ReceivePort();
  final ackPort = ReceivePort();
  final inputs = StreamIterator<dynamic>(inputPort);
  final acknowledgments = StreamIterator<dynamic>(ackPort);
  output.send(['ready', inputPort.sendPort, ackPort.sendPort]);
  Stream<List<int>> source() async* {
    while (true) {
      output.send(['input']);
      if (!await inputs.moveNext() || inputs.current == null) return;
      yield inputs.current as List<int>;
    }
  }

  Future<void> emit(List<int> bytes) async {
    output.send(['data', bytes]);
    await acknowledgments.moveNext();
  }

  try {
    final key = SecretKey(initialization[1] as List<int>);
    final nonce = initialization[2] as List<int>;
    final mac = Completer<Mac>();
    await emit(nonce);
    await for (final bytes
        in AesCtr.with256bits(macAlgorithm: Hmac.sha256()).encryptStream(
          source(),
          secretKey: key,
          nonce: nonce,
          onMac: mac.complete,
        )) {
      await emit(bytes);
    }
    await emit((await mac.future).bytes);
    output.send(['done']);
  } catch (_) {
    output.send(['error']);
  } finally {
    inputPort.close();
    ackPort.close();
  }
}
