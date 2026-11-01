import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_storage/src/shared/background_backup_runner.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BackgroundBackupRunner.thumbnailObjectKey', () {
    test('stores previews as opaque content-shaped objects', () {
      final key = BackgroundBackupRunner.thumbnailObjectKey(
        ownerPrefix: 'users/user-123',
        objectKey: 'users/user-123/folders/docs/objects/aa/bb/token-123',
      );

      expect(
        key,
        matches(
          RegExp(
            r'^users/user-123/folders/docs/objects/'
            r'[a-z0-9_-]{2}/[a-z0-9_-]{2}/[A-Za-z0-9_-]{22}$',
          ),
        ),
      );
      expect(key, isNot(contains('thumbnail')));
    });

    test('hashes a legacy source without exposing its path', () {
      final key = BackgroundBackupRunner.thumbnailObjectKey(
        ownerPrefix: 'users/user-123',
        objectKey: 'users/user-123/Photos/private-family.jpg',
      );

      expect(key, startsWith('users/user-123/objects/'));
      expect(key, isNot(contains('private-family.jpg')));
    });
  });

  group('BackgroundBackupRunner.localItemDebugLabel', () {
    test('is stable within one diagnostic session without disclosure', () {
      const path = r'C:\Users\person\Pictures\private-family-photo.jpg';
      final diagnosticKey = List<int>.generate(32, (index) => index);

      final first = BackgroundBackupRunner.localItemDebugLabel(
        path,
        diagnosticKey: diagnosticKey,
      );
      final second = BackgroundBackupRunner.localItemDebugLabel(
        path,
        diagnosticKey: diagnosticKey,
      );
      final other = BackgroundBackupRunner.localItemDebugLabel(
        r'C:\Users\person\Pictures\other.jpg',
        diagnosticKey: diagnosticKey,
      );

      expect(first, second);
      expect(first, matches(RegExp(r'^local-item-[a-f0-9]{12}$')));
      expect(first, isNot(other));
      expect(first, isNot(contains('person')));
      expect(first, isNot(contains('photo')));
      expect(first, isNot(contains('.jpg')));
    });

    test('cannot be correlated across independent diagnostic sessions', () {
      const path = r'C:\Users\person\Pictures\private-family-photo.jpg';
      final first = BackgroundBackupRunner.localItemDebugLabel(
        path,
        diagnosticKey: List<int>.filled(32, 7),
      );
      final second = BackgroundBackupRunner.localItemDebugLabel(
        path,
        diagnosticKey: List<int>.filled(32, 8),
      );

      expect(first, isNot(second));
    });

    test('rejects diagnostic keys that are too short', () {
      expect(
        () => BackgroundBackupRunner.localItemDebugLabel(
          'private-item',
          diagnosticKey: List<int>.filled(15, 1),
        ),
        throwsArgumentError,
      );
    });
  });

  group('BackgroundBackupRunner privacy-safe failures', () {
    test('maps exceptions into bounded operational categories', () {
      expect(
        BackgroundBackupRunner.errorCategory(
          const FileSystemException('private path failed'),
        ),
        'filesystem',
      );
      expect(
        BackgroundBackupRunner.errorCategory(TimeoutException('private')),
        'timeout',
      );
      expect(
        BackgroundBackupRunner.errorCategory(const FormatException('private')),
        'format',
      );
      expect(
        BackgroundBackupRunner.errorCategory(ArgumentError('private')),
        'invalid-input',
      );
      expect(
        BackgroundBackupRunner.errorCategory(StateError('private')),
        'operational',
      );
    });

    test('logs only event, category, and an opaque item reference', () {
      final messages = <String>[];
      final originalDebugPrint = debugPrint;
      addTearDown(() => debugPrint = originalDebugPrint);
      debugPrint = (message, {wrapWidth}) {
        if (message != null) messages.add(message);
      };
      const itemReference = 'local-item-0123456789ab';

      BackgroundBackupRunner.logFailure(
        'backup',
        'File upload failed',
        const FileSystemException(
          'password=hunter2',
          r'C:\Users\person\Pictures\private-family-photo.jpg',
        ),
        itemReference: itemReference,
      );

      expect(messages, hasLength(1));
      final message = messages.single;
      expect(message, contains('event=file_upload_failed'));
      expect(message, contains('category=filesystem'));
      expect(message, contains('item=$itemReference'));
      expect(message, isNot(contains('hunter2')));
      expect(message, isNot(contains('person')));
      expect(message, isNot(contains('photo')));
    });

    test('drops a caller-supplied reference that is not opaque', () {
      final messages = <String>[];
      final originalDebugPrint = debugPrint;
      addTearDown(() => debugPrint = originalDebugPrint);
      debugPrint = (message, {wrapWidth}) {
        if (message != null) messages.add(message);
      };

      BackgroundBackupRunner.logFailure(
        'backup',
        'watcher start',
        StateError('private'),
        itemReference: r'C:\Users\person\Family Photos',
      );

      expect(messages, hasLength(1));
      expect(messages.single, contains('event=watcher_start'));
      expect(messages.single, isNot(contains(' item=')));
      expect(messages.single, isNot(contains('person')));
      expect(messages.single, isNot(contains('Family Photos')));
    });
  });

  group('BackgroundBackupRunner.opaqueObjectKey', () {
    test('does not disclose backup or folder names', () {
      final objectKey = BackgroundBackupRunner.opaqueObjectKey(
        ownerPrefix: 'account_opaque',
        random: Random(42),
      );

      expect(
        objectKey,
        matches(
          RegExp(
            r'^account_opaque/objects/[a-z0-9_-]{2}/'
            r'[a-z0-9_-]{2}/[A-Za-z0-9_-]{22}$',
          ),
        ),
      );
      expect(objectKey, isNot(contains('Backups')));
      expect(objectKey, isNot(contains('Photos')));
      expect(objectKey, isNot(contains('report')));
    });

    test('generates independent object identities', () {
      final random = Random(7);
      final first = BackgroundBackupRunner.opaqueObjectKey(
        ownerPrefix: 'account_opaque',
        random: random,
      );
      final second = BackgroundBackupRunner.opaqueObjectKey(
        ownerPrefix: 'account_opaque',
        random: random,
      );

      expect(first, isNot(second));
    });

    test('normalizes a trailing slash without changing the opaque layout', () {
      final objectKey = BackgroundBackupRunner.opaqueObjectKey(
        ownerPrefix: 'account_opaque///',
        random: Random(4),
      );

      expect(objectKey, startsWith('account_opaque/objects/'));
      expect(objectKey, isNot(contains('//')));
    });
  });
}
