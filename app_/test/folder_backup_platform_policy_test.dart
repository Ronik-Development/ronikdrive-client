import 'package:cloud_storage/src/shared/folder_backup_platform_policy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS requires a saved folder grant before any directory access', () {
    expect(
      supportsPersistentFolderBackups(
        isWeb: false,
        platform: TargetPlatform.macOS,
      ),
      isTrue,
    );
    expect(
      canRunPersistentBackupConfig(
        isWeb: false,
        platform: TargetPlatform.macOS,
        photoLibrary: false,
      ),
      isFalse,
    );
    // A malformed or migrated configuration cannot bypass the folder gate by
    // claiming to be a Photo Library backup on an unsupported Apple platform.
    expect(
      canRunPersistentBackupConfig(
        isWeb: false,
        platform: TargetPlatform.macOS,
        photoLibrary: true,
      ),
      isFalse,
    );
  });

  test(
    'native folder backup stays available only with durable directory access',
    () {
      for (final platform in TargetPlatform.values) {
        expect(
          canRunPersistentBackupConfig(
            isWeb: false,
            platform: platform,
            photoLibrary: false,
          ),
          platform == TargetPlatform.windows ||
              platform == TargetPlatform.linux,
          reason: platform.name,
        );
      }
    },
  );

  test(
    'unavailable folder backup explains the remaining platform features',
    () {
      expect(
        persistentFolderBackupUnavailableMessage(
          isWeb: false,
          platform: TargetPlatform.iOS,
        ),
        contains('system conditions'),
      );
      expect(
        persistentFolderBackupUnavailableMessage(
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        contains('choose files to upload'),
      );
      expect(
        persistentFolderBackupUnavailableMessage(
          isWeb: false,
          platform: TargetPlatform.macOS,
        ),
        contains('Choose this folder again'),
      );
    },
  );

  test('iOS Photo Library backup retains its separate authorization path', () {
    expect(
      canRunPersistentBackupConfig(
        isWeb: false,
        platform: TargetPlatform.iOS,
        photoLibrary: true,
      ),
      isTrue,
    );
    expect(
      canRunPersistentBackupConfig(
        isWeb: false,
        platform: TargetPlatform.android,
        photoLibrary: true,
      ),
      isFalse,
    );
  });

  test('browser and unsupported native runtimes never run saved backups', () {
    for (final platform in TargetPlatform.values) {
      for (final photoLibrary in [false, true]) {
        expect(
          canRunPersistentBackupConfig(
            isWeb: true,
            platform: platform,
            photoLibrary: photoLibrary,
            hasFolderBookmark: true,
          ),
          isFalse,
        );
      }
    }
    for (final platform in [TargetPlatform.fuchsia]) {
      expect(
        supportsPersistentFolderBackups(isWeb: false, platform: platform),
        isFalse,
      );
    }
  });

  test('only supported Apple folders are enabled by a saved grant', () {
    for (final platform in TargetPlatform.values) {
      expect(
        canRunPersistentBackupConfig(
          isWeb: false,
          platform: platform,
          photoLibrary: false,
          hasFolderBookmark: true,
        ),
        [
          TargetPlatform.windows,
          TargetPlatform.linux,
          TargetPlatform.macOS,
          TargetPlatform.iOS,
        ].contains(platform),
      );
    }
  });
}
