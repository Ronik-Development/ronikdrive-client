import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all new image upload paths reuse one bounded source snapshot', () {
    final workspaceSource = File(
      'lib/src/home/workspace_home_page.dart',
    ).readAsStringSync();
    final workerSource = File(
      'lib/src/shared/background_backup_types.dart',
    ).readAsStringSync();

    expect(
      RegExp(r'captureBoundedImageUploadSource\(').allMatches(workspaceSource),
      hasLength(greaterThanOrEqualTo(2)),
    );
    expect(workerSource, contains('captureBoundedImageUploadSource('));
    expect(
      workspaceSource,
      isNot(
        contains('_generateThumbnailBytes(\n                        file,'),
      ),
    );
    expect(
      workspaceSource,
      isNot(
        contains(
          '_generateThumbnailBytes(\n                        XFile(file.path),',
        ),
      ),
    );
    expect(workerSource, isNot(contains('_generateThumbnailBytes(file)')));
    expect(
      workerSource,
      contains('derivativeTimeout: imageThumbnailDerivativeTimeout'),
    );
  });

  test('successful backup logs do not expose item references or sizes', () {
    final sources = <String>[
      'lib/src/home/workspace_home_page.dart',
      'lib/src/shared/background_backup_types.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');

    expect(sources, isNot(contains('file_upload_start item=')));
    expect(sources, isNot(contains('file_upload_start bytes=')));
    expect(sources, isNot(contains('file_upload_completed item=')));
    expect(sources, isNot(contains('Background upload starting for')));
    expect(sources, isNot(contains('Background upload completed for')));
  });

  test(
    'preview recovery is bounded and only explicit retry may request unlock',
    () {
      final workspaceSource = File(
        'lib/src/home/workspace_home_page.dart',
      ).readAsStringSync();
      final widgetSource = File(
        'lib/src/home/workspace_home_page_supporting_types.dart',
      ).readAsStringSync();
      final storageSource = File(
        'lib/src/storage/wasabi_storage_service.dart',
      ).readAsStringSync();

      expect(
        workspaceSource,
        contains('normalizeStoredImageThumbnail(stream)'),
      );
      expect(workspaceSource, contains('maxBytes: _maxInlinePreviewBytes'));
      expect(
        workspaceSource,
        contains('maxPlaintextBytes: imageThumbnailMaxStoredBytes'),
      );
      expect(workspaceSource, contains('interactive: interactive'));
      expect(storageSource, contains('maxPlaintextBytes'));
      expect(storageSource, contains('WasabiDownloadLimitException'));
      expect(
        RegExp(
          r'_loadThumbnail\(force: true,\s*interactive: true\)',
        ).allMatches(widgetSource),
        hasLength(greaterThanOrEqualTo(2)),
      );
      expect(widgetSource, contains('_loadThumbnail(force: true);'));
      expect(widgetSource, contains('Unlock or retry image preview'));
    },
  );

  test('one upload intent covers selection, unlock, import, and drop', () {
    final workspaceSource = File(
      'lib/src/home/workspace_home_page.dart',
    ).readAsStringSync();

    expect(workspaceSource, contains('Future<void> _runUploadIntent('));
    expect(workspaceSource, contains('Future<void> _pickAndUploadFiles({'));
    expect(workspaceSource, contains('}) => _runUploadIntent('));
    expect(
      RegExp(r'=> _runUploadIntent\(').allMatches(workspaceSource),
      hasLength(greaterThanOrEqualTo(3)),
    );
    expect(workspaceSource, contains('_transferController.uploadIntentActive'));
    expect(
      RegExp(
        r'onDragDone: \(details\) \{[\s\S]*?unawaited\(\s*_runUploadIntent\(',
      ).hasMatch(workspaceSource),
      isTrue,
    );
  });

  test('automatic preview retries remain loading until exhausted', () {
    final widgetSource = File(
      'lib/src/home/workspace_home_page_supporting_types.dart',
    ).readAsStringSync();

    expect(
      widgetSource,
      contains('ImageThumbnailRetryPolicy.canRetryAutomatically('),
    );
    expect(widgetSource, contains('_loading = retryScheduled;'));
    expect(
      widgetSource,
      contains('_failed = bytes == null && !retryScheduled;'),
    );
    expect(widgetSource, contains('_failed = !retryScheduled;'));
  });
}
