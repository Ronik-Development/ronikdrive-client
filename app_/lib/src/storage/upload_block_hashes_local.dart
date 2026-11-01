import 'dart:typed_data';
import 'package:crypto/crypto.dart';

Stream<(Uint8List, String)> hashUploadBlocks(Stream<Uint8List> blocks) async* {
  await for (final block in blocks) {
    yield (block, sha256.convert(block).toString());
  }
}
