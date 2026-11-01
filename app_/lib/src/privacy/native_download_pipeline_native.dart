import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive_io.dart' hide ZLibEncoder;
import 'package:cryptography/cryptography.dart';
import 'temporary_plaintext_lease.dart';

/// Legacy nonce+ciphertext+MAC framing requires a bounded two-pass read. Only
/// ciphertext is staged; authenticated plaintext is yielded without a full buffer.
Stream<List<int>> decryptFramedDownload(
  Stream<List<int>> encrypted, {
  required SecretKey key,
  required TemporaryPlaintextLeaseManager manager,
  required void Function() checkAccess,
}) async* {
  final staged = await manager.create(extension: '.bin');
  try {
    await staged.writeStream(encrypted, checkAccess: checkAccess);
    final algorithm = AesCtr.with256bits(macAlgorithm: Hmac.sha256());
    final length = await staged.file.length(),
        nonceLength = algorithm.nonceLength,
        macLength = algorithm.macAlgorithm.macLength;
    if (length < nonceLength + macLength) {
      throw const FormatException('The encrypted file is incomplete.');
    }
    final input = await staged.file.open(mode: FileMode.read);
    late List<int> nonce, mac;
    try {
      nonce = await input.read(nonceLength);
      await input.setPosition(length - macLength);
      mac = await input.read(macLength);
    } finally {
      await input.close();
    }
    checkAccess();
    await for (final chunk in algorithm.decryptStream(
      staged.file.openRead(nonceLength, length - macLength),
      secretKey: key,
      nonce: nonce,
      mac: Mac(mac),
    )) {
      checkAccess();
      yield chunk;
    }
    checkAccess();
  } finally {
    await staged.release();
  }
}

class _PrecompressedFileContent extends FileContentStream {
  _PrecompressedFileContent(super.stream);
  @override
  bool get isCompressed => true;
  @override
  InputStream getStream({bool decompress = true}) {
    if (decompress) throw StateError('ZIP staging is a compressed stream.');
    return stream;
  }
}

Future<void> _addBoundedZipEntry(
  ZipFileEncoder encoder,
  File source,
  String name,
  File staged,
) async {
  var size = 0, crc = 0;
  IOSink? sink;
  InputFileStream? input;
  try {
    sink = staged.openWrite();
    final observed = source.openRead().map((chunk) {
      size += chunk.length;
      crc = getCrc32(chunk, crc);
      return chunk;
    });
    await sink.addStream(ZLibEncoder(raw: true, level: 6).bind(observed));
    await sink.flush();
    await sink.close();
    sink = null;
    input = InputFileStream(staged.path);
    final entry = ArchiveFile.file(name, size, _PrecompressedFileContent(input))
      ..crc32 = crc
      ..compression = CompressionType.deflate;
    encoder.addArchiveFile(entry);
  } finally {
    try {
      await sink?.close();
    } catch (_) {}
    await input?.close();
    if (await staged.exists()) await staged.delete();
  }
}

void _zipWorker(List<Object> start) async {
  final replies = start[0] as SendPort, commands = ReceivePort();
  final encoder = ZipFileEncoder();
  try {
    encoder.create(start[1] as String);
    replies.send(commands.sendPort);
    await for (final raw in commands) {
      final command = raw as List;
      try {
        if (command[0] == 'add') {
          await _addBoundedZipEntry(
            encoder,
            File(command[1] as String),
            command[2] as String,
            File(
              '${File(start[1] as String).parent.path}/compressed-entry.tmp',
            ),
          );
          replies.send(true);
        } else if (command[0] == 'close') {
          await encoder.close();
          replies.send(true);
          break;
        }
      } catch (_) {
        try {
          await encoder.close();
        } catch (_) {}
        replies.send(false);
        break;
      }
    }
  } catch (_) {
    try {
      await encoder.close();
    } catch (_) {}
    replies.send(false);
  } finally {
    commands.close();
  }
}

/// Compression runs outside the UI isolate; only private paths and local entry
/// names cross this boundary, never an API, diagnostic or operator channel.
class NativeStreamingZip {
  NativeStreamingZip._(
    this._isolate,
    this._port,
    this._replies,
    this._commands,
  );
  final Isolate _isolate;
  final ReceivePort _port;
  final StreamIterator<dynamic> _replies;
  final SendPort _commands;
  bool _closed = false;
  static Future<NativeStreamingZip> create(
    TemporaryPlaintextLease lease,
  ) async {
    if (!lease.isActive) throw StateError('The ZIP lease expired.');
    final port = ReceivePort();
    final replies = StreamIterator<dynamic>(port);
    final isolate = await Isolate.spawn(
      _zipWorker,
      <Object>[port.sendPort, lease.file.path],
      onError: port.sendPort,
      onExit: port.sendPort,
    );
    if (!await replies.moveNext() || replies.current is! SendPort) {
      isolate.kill(priority: Isolate.immediate);
      port.close();
      throw StateError('The private ZIP could not be started.');
    }
    return NativeStreamingZip._(
      isolate,
      port,
      replies,
      replies.current as SendPort,
    );
  }

  Future<void> _request(List<Object> command) async {
    if (_closed) throw StateError('The private ZIP is closed.');
    _commands.send(command);
    if (!await _replies.moveNext() || _replies.current != true) {
      cancel();
      throw StateError('The private ZIP could not be completed.');
    }
  }

  Future<void> add(TemporaryPlaintextLease lease, String name) async {
    if (!lease.isActive ||
        name.isEmpty ||
        name.startsWith('/') ||
        name.split('/').contains('..') ||
        name.contains('\\')) {
      throw const FormatException('The private ZIP entry is invalid.');
    }
    await _request(['add', lease.file.path, name]);
  }

  Future<void> close() async {
    await _request(['close']);
    cancel();
  }

  void cancel() {
    if (_closed) return;
    _closed = true;
    _isolate.kill(priority: Isolate.immediate);
    _port.close();
    unawaited(_replies.cancel());
  }
}
