import 'dart:convert';
import 'dart:io';

const _matrixPath = 'test/test_matrix.json';

const _requiredCoverage = <String, Set<String>>{
  'platform': {'android', 'web', 'desktop'},
  'auth': {
    'new-account',
    'existing-account',
    'wrong-password',
    'session-restore',
  },
  'encryption': {
    'standard',
    'secure-locked',
    'secure-unlocked',
    'legacy-secured-migration',
  },
  'source': {'local-file', 'folder', 'backup', 'cloud-import'},
  'file': {'text-small', 'image-thumbnail', 'binary', 'empty', 'large-sharded'},
  'state': {
    'online',
    'offline',
    'refresh-reopen',
    'second-device',
    'network-error',
  },
  'operation': {
    'login',
    'upload',
    'open',
    'rename',
    'delete',
    'download',
    'offline',
    'share-link',
    'sync',
  },
};

const _cases = <Map<String, String>>[
  {
    'id': 'auth-new-standard-upload-open',
    'title':
        'New Android account uploads and opens standard encrypted text file',
    'platform': 'android',
    'auth': 'new-account',
    'encryption': 'standard',
    'source': 'local-file',
    'file': 'text-small',
    'state': 'online',
    'operation': 'upload',
    'expected':
        'File name is readable after login and file opens without secure prompt.',
  },
  {
    'id': 'auth-existing-session-restore-web',
    'title': 'Existing web session restores standard file names after refresh',
    'platform': 'web',
    'auth': 'session-restore',
    'encryption': 'standard',
    'source': 'local-file',
    'file': 'image-thumbnail',
    'state': 'refresh-reopen',
    'operation': 'open',
    'expected':
        'Names and thumbnails decrypt after refresh with no passphrase dialog.',
  },
  {
    'id': 'auth-wrong-password-blocks-login',
    'title': 'Wrong password does not unlock account data',
    'platform': 'android',
    'auth': 'wrong-password',
    'encryption': 'standard',
    'source': 'local-file',
    'file': 'text-small',
    'state': 'online',
    'operation': 'login',
    'expected': 'Login fails and no file metadata or object data is shown.',
  },
  {
    'id': 'secure-locked-name-hidden',
    'title':
        'Secure file remains locked until secure mode passphrase is entered',
    'platform': 'android',
    'auth': 'existing-account',
    'encryption': 'secure-locked',
    'source': 'local-file',
    'file': 'large-sharded',
    'state': 'online',
    'operation': 'open',
    'expected':
        'List shows locked item and open action requests secure passphrase.',
  },
  {
    'id': 'secure-unlocked-sharded-download',
    'title': 'Secure sharded binary downloads after secure mode unlock',
    'platform': 'android',
    'auth': 'existing-account',
    'encryption': 'secure-unlocked',
    'source': 'local-file',
    'file': 'large-sharded',
    'state': 'online',
    'operation': 'download',
    'expected':
        'All shards download, decrypt, and reassemble into original bytes.',
  },
  {
    'id': 'legacy-secured-auto-migrates',
    'title': 'Legacy secured file decrypts with login key and becomes standard',
    'platform': 'web',
    'auth': 'existing-account',
    'encryption': 'legacy-secured-migration',
    'source': 'local-file',
    'file': 'text-small',
    'state': 'refresh-reopen',
    'operation': 'sync',
    'expected':
        'Name appears automatically and metadata changes to standard encryption.',
  },
  {
    'id': 'second-device-standard-multicast',
    'title': 'Phone upload appears on already-open desktop app',
    'platform': 'desktop',
    'auth': 'existing-account',
    'encryption': 'standard',
    'source': 'local-file',
    'file': 'image-thumbnail',
    'state': 'second-device',
    'operation': 'sync',
    'expected':
        'Desktop live list updates and decrypts file name and thumbnail.',
  },
  {
    'id': 'offline-standard-file',
    'title': 'Standard file can be saved for offline use',
    'platform': 'android',
    'auth': 'existing-account',
    'encryption': 'standard',
    'source': 'local-file',
    'file': 'binary',
    'state': 'offline',
    'operation': 'offline',
    'expected': 'Offline copy opens after network is disabled.',
  },
  {
    'id': 'network-error-upload-retry',
    'title': 'Interrupted upload does not create broken metadata',
    'platform': 'android',
    'auth': 'existing-account',
    'encryption': 'standard',
    'source': 'local-file',
    'file': 'large-sharded',
    'state': 'network-error',
    'operation': 'upload',
    'expected':
        'User sees failure, no unreadable partial file appears, retry succeeds.',
  },
  {
    'id': 'folder-upload-nested-files',
    'title': 'Folder upload keeps nested structure and encrypted names',
    'platform': 'desktop',
    'auth': 'existing-account',
    'encryption': 'standard',
    'source': 'folder',
    'file': 'text-small',
    'state': 'online',
    'operation': 'upload',
    'expected':
        'Nested folders and files appear in correct location with readable names.',
  },
  {
    'id': 'backup-empty-file',
    'title': 'Backup handles empty file without retry loop',
    'platform': 'desktop',
    'auth': 'existing-account',
    'encryption': 'standard',
    'source': 'backup',
    'file': 'empty',
    'state': 'online',
    'operation': 'upload',
    'expected': 'Backup scan completes and records no corrupt object.',
  },
  {
    'id': 'cloud-import-rename-delete',
    'title': 'Cloud-imported file can be renamed and deleted',
    'platform': 'web',
    'auth': 'existing-account',
    'encryption': 'standard',
    'source': 'cloud-import',
    'file': 'binary',
    'state': 'online',
    'operation': 'rename',
    'expected':
        'Rename updates encrypted display name; delete removes metadata and object.',
  },
  {
    'id': 'encrypted-link-blocked',
    'title': 'Raw link sharing is blocked for encrypted files',
    'platform': 'web',
    'auth': 'existing-account',
    'encryption': 'standard',
    'source': 'local-file',
    'file': 'text-small',
    'state': 'online',
    'operation': 'share-link',
    'expected': 'Copy-link action refuses raw encrypted object URL.',
  },
  {
    'id': 'secure-share-after-unlock',
    'title': 'Secure file share exports decrypted copy only after unlock',
    'platform': 'android',
    'auth': 'existing-account',
    'encryption': 'secure-unlocked',
    'source': 'local-file',
    'file': 'binary',
    'state': 'online',
    'operation': 'download',
    'expected':
        'Share/download works only after secure passphrase and output bytes match source.',
  },
  {
    'id': 'delete-secure-shards',
    'title': 'Deleting secure file removes all shard objects',
    'platform': 'android',
    'auth': 'existing-account',
    'encryption': 'secure-unlocked',
    'source': 'local-file',
    'file': 'large-sharded',
    'state': 'online',
    'operation': 'delete',
    'expected': 'Metadata disappears and every shard key is deleted.',
  },
  {
    'id': 'secure-hmac-shard-paths',
    'title': 'Secure uploads use passphrase-derived opaque shard paths',
    'platform': 'web',
    'auth': 'existing-account',
    'encryption': 'secure-unlocked',
    'source': 'local-file',
    'file': 'large-sharded',
    'state': 'online',
    'operation': 'upload',
    'expected':
        'Uploaded shard keys are under the object parts prefix but do not reveal sequential indexes.',
  },
  {
    'id': 'secure-refresh-stale-prompt',
    'title': 'Stale secure files prompt for non-blocking passphrase refresh',
    'platform': 'desktop',
    'auth': 'existing-account',
    'encryption': 'secure-unlocked',
    'source': 'local-file',
    'file': 'binary',
    'state': 'refresh-reopen',
    'operation': 'sync',
    'expected':
        'Overdue secure files show a refresh prompt, accept the passphrase locally, and update the next due date without blocking access.',
  },
];

void main(List<String> args) {
  final expected = _canonicalJson(_generatedMatrix());
  final file = File(_matrixPath);

  if (args.contains('--write')) {
    file
      ..createSync(recursive: true)
      ..writeAsStringSync('$expected\n');
    stdout.writeln('Wrote $_matrixPath');
    return;
  }

  if (!file.existsSync()) {
    stderr.writeln(
      'Missing $_matrixPath. Run: dart run tool/verify_test_matrix.dart --write',
    );
    exit(1);
  }

  final actual = _canonicalJson(jsonDecode(file.readAsStringSync()));
  if (actual != expected) {
    stderr.writeln(
      '$_matrixPath is stale. Run: dart run tool/verify_test_matrix.dart --write',
    );
    exit(1);
  }

  final errors = _validateCoverage(_cases);
  if (errors.isNotEmpty) {
    for (final error in errors) {
      stderr.writeln(error);
    }
    exit(1);
  }

  stdout.writeln('Test matrix OK: ${_cases.length} risk-based scenarios.');
}

Map<String, Object> _generatedMatrix() {
  return {
    'version': 1,
    'policy': 'risk-based',
    'requiredCoverage': {
      for (final entry in _requiredCoverage.entries)
        entry.key: entry.value.toList()..sort(),
    },
    'cases': _cases,
  };
}

List<String> _validateCoverage(List<Map<String, String>> cases) {
  final errors = <String>[];
  final ids = <String>{};

  for (final testCase in cases) {
    final id = testCase['id'];
    if (id == null || id.trim().isEmpty) {
      errors.add('Test case missing id: $testCase');
      continue;
    }
    if (!ids.add(id)) {
      errors.add('Duplicate test case id: $id');
    }
    for (final field in <String>[
      'title',
      'platform',
      'auth',
      'encryption',
      'source',
      'file',
      'state',
      'operation',
      'expected',
    ]) {
      if ((testCase[field] ?? '').trim().isEmpty) {
        errors.add('$id missing $field');
      }
    }
  }

  for (final requirement in _requiredCoverage.entries) {
    final covered = cases.map((testCase) => testCase[requirement.key]).toSet();
    final missing = requirement.value.difference(covered);
    if (missing.isNotEmpty) {
      errors.add('${requirement.key} coverage missing: ${missing.join(', ')}');
    }
  }

  return errors;
}

String _canonicalJson(Object value) {
  return const JsonEncoder.withIndent('  ').convert(value);
}
