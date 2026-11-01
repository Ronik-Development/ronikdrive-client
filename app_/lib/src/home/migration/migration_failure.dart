import 'dart:async';

enum MigrationFailureAction { connect, browse, selectFolder, importFiles }

/// Returns recovery guidance without copying provider responses, remote paths,
/// account identifiers, or exception text into the interface.
String migrationFailureMessage(MigrationFailureAction action, Object error) {
  final connectionHint = error is TimeoutException
      ? 'The request timed out. Check your connection and try again.'
      : null;
  if (connectionHint != null) {
    return connectionHint;
  }

  return switch (action) {
    MigrationFailureAction.connect =>
      'Could not connect to this storage provider. Check your sign-in and connection, then try again.',
    MigrationFailureAction.browse =>
      'Could not open this provider folder. Check your connection and try again.',
    MigrationFailureAction.selectFolder =>
      'Could not inspect the entire folder. Nothing new was selected; open the folder and select individual files, or try again.',
    MigrationFailureAction.importFiles =>
      'The import could not finish. Any completed files remain encrypted; retry only items still missing.',
  };
}
