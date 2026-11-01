import 'dart:async';
import 'package:cryptography/cryptography.dart';
import 'upload_chunks.dart';

Stream<List<int>> encryptUploadStream(
  Stream<List<int>> input,
  SecretKey key,
  List<int> nonce,
) async* {
  final algorithm = AesCtr.with256bits(macAlgorithm: Hmac.sha256());
  final mac = Completer<Mac>();
  yield nonce;
  await for (final chunk in algorithm.encryptStream(
    boundedUploadChunks(input),
    secretKey: key,
    nonce: nonce,
    onMac: mac.complete,
  )) {
    yield chunk;
    await Future<void>.delayed(Duration.zero);
  }
  yield (await mac.future).bytes;
}
