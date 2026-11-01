import 'dart:convert';
import 'package:cloud_storage/src/privacy/restore_sample_verifier.dart';
import 'package:cloud_storage/src/security/workspace_metadata_encryption_service.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final key = SecretKey(List.filled(32, 7));
  final data = utf8.encode('Synthetic restore bytes');
  test('authenticated length and keyed content evidence agree', () async {
    final tag = await WorkspaceMetadataEncryptionService().contentIntegrityTag(
      sha256Base64: base64Encode(crypto.sha256.convert(data).bytes),
      key: key,
    );
    final result = await verifyRestoreSample(
      Stream.value(data),
      authenticated: true,
      expectedPlaintextBytes: data.length,
      integrityTag: tag,
      key: key,
    );
    expect(result.verified, true);
    expect(result.digestVerified, true);
    expect(result.bytesRead, data.length);
  });
  test('wrong nonempty content and wrong size do not verify', () async {
    final tag = await WorkspaceMetadataEncryptionService().contentIntegrityTag(
      sha256Base64: base64Encode(crypto.sha256.convert(data).bytes),
      key: key,
    );
    await expectLater(
      verifyRestoreSample(
        Stream.value(data),
        authenticated: true,
        expectedPlaintextBytes: data.length + 1,
      ),
      throwsFormatException,
    );
    await expectLater(
      verifyRestoreSample(
        Stream.value([1, 2, 3]),
        authenticated: true,
        integrityTag: tag,
        key: key,
      ),
      throwsFormatException,
    );
  });
  test(
    'legacy bare hashes and readable plaintext do not become authenticated evidence',
    () async {
      final result = await verifyRestoreSample(
        Stream.value(data),
        authenticated: true,
        integrityTag: base64Encode(crypto.sha256.convert(data).bytes),
      );
      expect(result.verified, false);
      expect(result.digestVerified, false);
      expect(
        (await verifyRestoreSample(
          Stream.value(data),
          authenticated: false,
          expectedPlaintextBytes: data.length,
        )).verified,
        false,
      );
    },
  );
  test('late MAC failure and revocation prevent a successful sample', () async {
    Stream<List<int>> broken() async* {
      yield data;
      throw SecretBoxAuthenticationError();
    }

    await expectLater(
      verifyRestoreSample(
        broken(),
        authenticated: true,
        expectedPlaintextBytes: data.length,
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
    await expectLater(
      verifyRestoreSample(
        Stream.value(data),
        authenticated: true,
        checkAccess: () => throw StateError('Synthetic revoked access'),
      ),
      throwsStateError,
    );
  });
  test(
    'authenticated zero-byte file is valid with known plaintext length',
    () async {
      expect(
        (await verifyRestoreSample(
          Stream.value([]),
          authenticated: true,
          expectedPlaintextBytes: 0,
        )).verified,
        true,
      );
    },
  );
}
