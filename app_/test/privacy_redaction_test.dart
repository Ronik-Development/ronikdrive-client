import 'package:flutter_test/flutter_test.dart';

import 'package:cloud_storage/src/privacy/privacy_redaction.dart';

void main() {
  test('redaction removes secrets, identity values, URLs, and home users', () {
    final redacted = redactDiagnosticText(
      'Bearer secret-token private@example.com '
      'uid=abc123 owner="user-123" objectKey=user/file.pdf password=hunter2 '
      'Reconciling usage for user "user-456". '
      'Upload failed for report.pdf. '
      'https://example.com/callback?token=secret#fragment '
      r'C:\Users\tom\project /home/alice/project',
    );

    for (final sensitiveValue in [
      'secret-token',
      'private@example.com',
      'abc123',
      'user-123',
      'user-456',
      'user/file.pdf',
      'report.pdf',
      'hunter2',
      'token=secret',
      r'\tom\',
      '/alice/',
    ]) {
      expect(redacted, isNot(contains(sensitiveValue)));
    }
  });

  test(
    'redaction removes extensionless labels, provider refs, and full paths',
    () {
      final redacted = redactDiagnosticText(
        'fileName="Quarterly Strategy" folderName=Board '
        'remoteFolder=Leadership displayName="Alice Manager" '
        'companyName=Northwind workspaceName="Acquisitions Room" '
        'https://storage.example/user_0123456789abcdef0123456789abcdef/'
        'objects/aa/opaque-token?signature=private '
        'user_0123456789abcdef0123456789abcdef/objects/aa/opaque-token '
        'encryptedName=enc--abcdefghijklmnopqrstuv '
        r'localPath="C:\Users\Alice\Board Papers\Quarterly Strategy" '
        'path="/home/alice/Board Papers/Quarterly Strategy" '
        r'C:\Users\Alice\Board Papers\Quarterly Strategy:42:7 objectKey=safe',
      );

      for (final sensitiveValue in <String>[
        'Quarterly Strategy',
        'Leadership',
        'Alice Manager',
        'Northwind',
        'Acquisitions Room',
        'storage.example',
        'opaque-token',
        'enc--abcdefghijklmnopqrstuv',
        'Board Papers',
        'Quarterly Strategy:42',
        r'\Alice\',
        '/alice/',
      ]) {
        expect(redacted, isNot(contains(sensitiveValue)));
      }
    },
  );

  test('redaction removes unquoted paths with spaces before exceptions', () {
    final redacted = redactDiagnosticText(
      r'Backup failed for C:\Users\Alice\Family Photos\summer beach.jpg: '
      'FileSystemException and '
      'scan failed for /home/alice/Family Photos/summer beach.jpg: '
      'StateError',
    );

    expect(redacted, contains('<path-redacted>: FileSystemException'));
    expect(redacted, contains('<path-redacted>: StateError'));
    expect(redacted, isNot(contains('Alice')));
    expect(redacted, isNot(contains('Family Photos')));
    expect(redacted, isNot(contains('summer beach')));
  });
}
