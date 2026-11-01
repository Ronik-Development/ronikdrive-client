import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import '../security/workspace_metadata_encryption_service.dart';

class RestoreSampleEvidence {
  const RestoreSampleEvidence({
    required this.bytesRead,
    required this.authenticated,
    required this.lengthVerified,
    required this.digestVerified,
  });
  final int bytesRead;
  final bool authenticated, lengthVerified, digestVerified;
  bool get verified => authenticated && (lengthVerified || digestVerified);
}

Future<RestoreSampleEvidence> verifyRestoreSample(
  Stream<List<int>> stream, {
  required bool authenticated,
  int? expectedPlaintextBytes,
  String? integrityTag,
  SecretKey? key,
  void Function()? checkAccess,
}) async {
  if (expectedPlaintextBytes != null && expectedPlaintextBytes < 0) {
    throw const FormatException('Invalid plaintext size.');
  }
  var size = 0;
  final watched = () async* {
    await for (final chunk in stream) {
      checkAccess?.call();
      size += chunk.length;
      if (expectedPlaintextBytes != null && size > expectedPlaintextBytes) {
        throw const FormatException('Restored length does not match.');
      }
      yield chunk;
    }
    checkAccess?.call();
  }();
  // Completion must also authenticate the download source; never finalize early.
  final digest = await crypto.sha256.bind(watched).first;
  if (expectedPlaintextBytes != null && size != expectedPlaintextBytes) {
    throw const FormatException('Restored length does not match.');
  }
  var digestVerified = false;
  if (integrityTag?.startsWith(
        WorkspaceMetadataEncryptionService.contentIntegrityTagPrefix,
      ) ==
      true) {
    if (key == null) throw StateError('The integrity key is unavailable.');
    final actual = await WorkspaceMetadataEncryptionService()
        .contentIntegrityTag(
          sha256Base64: base64Encode(digest.bytes),
          key: key,
        );
    final expected = integrityTag!;
    var difference = actual.length ^ expected.length;
    for (var i = 0; i < actual.length; i++) {
      difference |=
          actual.codeUnitAt(i) ^
          (i < expected.length ? expected.codeUnitAt(i) : 0);
    }
    if (difference != 0) {
      throw const FormatException(
        'Restored content does not match its protected digest.',
      );
    }
    digestVerified = true;
  }
  checkAccess?.call();
  return RestoreSampleEvidence(
    bytesRead: size,
    authenticated: authenticated,
    lengthVerified: expectedPlaintextBytes != null,
    digestVerified: digestVerified,
  );
}
