import 'package:flutter/foundation.dart';

/// Apple backups require a persisted security-scoped bookmark, checked per
/// configuration and held during every scan. Android still requires a
/// provider-aware tree reader rather than a converted raw filesystem path.
///
/// This policy does not restrict one-shot uploads made through a native picker,
/// recognize desktop worker arguments, or change login/startup registration.
bool supportsPersistentFolderBackups({
  required bool isWeb,
  required TargetPlatform platform,
}) =>
    !isWeb &&
    switch (platform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux ||
      TargetPlatform.iOS => true,
      TargetPlatform.android || TargetPlatform.fuchsia => false,
    };

/// Apply before touching a saved configuration's local path. Photo Library
/// backups use Apple's photo authorization rather than directory grants.
bool canRunPersistentBackupConfig({
  required bool isWeb,
  required TargetPlatform platform,
  required bool photoLibrary,
  bool hasFolderBookmark = false,
}) => photoLibrary
    ? !isWeb && platform == TargetPlatform.iOS
    : supportsPersistentFolderBackups(isWeb: isWeb, platform: platform) &&
          (!(platform == TargetPlatform.macOS ||
                  platform == TargetPlatform.iOS) ||
              hasFolderBookmark);

const String macosFolderBackupUnavailableMessage =
    'Choose this folder again to allow automatic backup across app restarts.';

String persistentFolderBackupUnavailableMessage({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  if (isWeb) return 'Automatic folder backup is not available in the browser.';
  return switch (platform) {
    TargetPlatform.macOS => macosFolderBackupUnavailableMessage,
    TargetPlatform.iOS =>
      'Choose this folder again to allow automatic backup. '
          'iOS schedules background work when system conditions allow it.',
    TargetPlatform.android =>
      'Automatic folder backup is not available on Android yet. '
          'You can still choose files to upload.',
    _ => 'Automatic folder backup is not available on this platform.',
  };
}
