import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'upload preview and download diagnostics contain no item names or errors',
    () {
      final source = File(
        'lib/src/home/workspace_home_page.dart',
      ).readAsStringSync();

      for (final prohibited in const <String>[
        r"debugPrint('Selected download failed: $error')",
        r"debugPrint('Failed to add ${file.name} to ZIP: $error')",
        r"debugPrint('ZIP download failed: $error')",
        r"debugPrint('Optional thumbnail upload failed: $error')",
        r"debugPrint('Upload failed for $displayName: $error')",
        r'''_logRuntime('upload', 'Upload failed for "$displayName": $error')''',
        r"debugPrint('Fallback thumbnail generation failed: $error')",
        r"debugPrint('Generated thumbnail repair failed: $error')",
        r"debugPrint('Failed to preview offline file ${file.name}: $error')",
        r"debugPrint('Migration download failed for $displayName: $error')",
        r'''_logRuntime(
            'migration',
            'Import preparation failed for "$displayName" from ${provider.displayName}: $error',
          )''',
      ]) {
        expect(source, isNot(contains(prohibited)), reason: prohibited);
      }

      for (final requiredEvent in const <String>[
        "'selected_file'",
        "'zip_entry'",
        "'zip_bundle'",
        "'optional_image_preview'",
        "'encrypted_source'",
        "'foreground_batch'",
        "'fallback_thumbnail_generation'",
        "'generated_thumbnail_repair'",
        "'offline_inline_preview'",
        "'provider_download'",
      ]) {
        expect(source, contains(requiredEvent), reason: requiredEvent);
      }

      for (final providerSource in const <String>[
        'lib/src/home/migration/google_drive_provider.dart',
        'lib/src/home/migration/onedrive_provider.dart',
        'lib/src/home/migration/dropbox_provider.dart',
      ]) {
        expect(
          File(providerSource).readAsStringSync(),
          isNot(contains(r'${response.body}')),
          reason: providerSource,
        );
      }
    },
  );
}
