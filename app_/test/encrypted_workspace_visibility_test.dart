import 'package:cloud_storage/src/security/encrypted_workspace_visibility.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('opaque encrypted labels never become user-facing names', () {
    const cipher = 'enc--abcdefghijklmnopqrstuv';

    expect(containsOpaqueEncryptedLabel(cipher), isTrue);
    expect(containsOpaqueEncryptedLabel('opaque.e.$cipher'), isTrue);
    expect(
      safeEncryptedDisplayLabel(
        placeholder: 'Encrypted file',
        encryptedLabel: cipher,
        candidate: cipher,
      ),
      'Encrypted file',
    );
    expect(
      safeEncryptedDisplayLabel(
        placeholder: 'Encrypted file',
        candidate: 'opaque.e.$cipher',
      ),
      'Encrypted file',
    );
  });

  test('protected local cache may restore a decrypted display label', () {
    expect(
      safeEncryptedDisplayLabel(
        placeholder: 'Encrypted file',
        encryptedLabel: 'enc--abcdefghijklmnopqrstuv',
        candidate: 'Quarterly strategy.png',
      ),
      'Quarterly strategy.png',
    );
  });

  test('Business member envelopes never request the Personal standard key', () {
    expect(
      requiresStandardWorkspaceKeyForLabel(
        isSecured: false,
        hasEncryptedLabel: true,
        hasEmbeddedEncryptedLabel: false,
        hasMemberKeyEnvelopes: true,
      ),
      isFalse,
    );
    expect(
      requiresStandardWorkspaceKeyForLabel(
        isSecured: false,
        hasEncryptedLabel: true,
        hasEmbeddedEncryptedLabel: false,
        hasMemberKeyEnvelopes: false,
      ),
      isTrue,
    );
  });
}
