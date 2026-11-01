import 'dart:io';

import 'package:cloud_storage/src/shared/web_upload_stream_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('webUploadByteRanges', () {
    test('keeps every browser read within the plaintext memory budget', () {
      final ranges = webUploadByteRanges(
        length: webUploadReadChunkBytes * 2 + 17,
      ).toList(growable: false);

      expect(ranges, <WebUploadByteRange>[
        (start: 0, endExclusive: webUploadReadChunkBytes),
        (
          start: webUploadReadChunkBytes,
          endExclusive: webUploadReadChunkBytes * 2,
        ),
        (
          start: webUploadReadChunkBytes * 2,
          endExclusive: webUploadReadChunkBytes * 2 + 17,
        ),
      ]);
      expect(
        ranges.every(
          (range) =>
              range.endExclusive - range.start <= webUploadReadChunkBytes,
        ),
        isTrue,
      );
    });

    test('honors a bounded thumbnail read and clamps invalid offsets', () {
      expect(
        webUploadByteRanges(
          length: 100,
          start: -20,
          endExclusive: 12,
          chunkBytes: 5,
        ).toList(growable: false),
        <WebUploadByteRange>[
          (start: 0, endExclusive: 5),
          (start: 5, endExclusive: 10),
          (start: 10, endExclusive: 12),
        ],
      );
      expect(webUploadByteRanges(length: 100, start: 200).toList(), isEmpty);
      expect(webUploadByteRanges(length: 100, chunkBytes: 0).toList(), isEmpty);
    });
  });

  test('browser picker never buffers or copies an entire selected file', () {
    final pickerSource = File(
      'lib/src/shared/web_folder_upload_picker_html.dart',
    ).readAsStringSync();
    final workspaceSource = File(
      'lib/src/home/workspace_home_page.dart',
    ).readAsStringSync();

    expect(pickerSource, contains('_browserFile.slice('));
    expect(pickerSource, contains('slice.arrayBuffer()'));
    expect(pickerSource, isNot(contains('browserFile.arrayBuffer()')));
    expect(pickerSource, isNot(contains('Uint8List.fromList')));
    expect(workspaceSource, contains('sizeBytes: file.sizeBytes'));
    expect(
      workspaceSource,
      contains('readStreamFactory: () => file.openRead()'),
    );
    expect(
      workspaceSource,
      contains('boundedReadStreamFactory: (endExclusive)'),
    );
  });

  test('web picker preserves user activation and encrypts before reading', () {
    final workspaceSource = File(
      'lib/src/home/workspace_home_page.dart',
    ).readAsStringSync();
    final filePickerStart = workspaceSource.indexOf(
      'Future<void> _pickAndUploadFiles',
    );
    final folderPickerStart = workspaceSource.indexOf(
      'Future<void> _pickAndUploadFolder',
    );
    final preparedLengthStart = workspaceSource.indexOf(
      'Future<int> _preparedUploadLength',
    );
    final filePickerSource = workspaceSource.substring(
      filePickerStart,
      preparedLengthStart,
    );
    final folderPickerSource = workspaceSource.substring(
      folderPickerStart,
      workspaceSource.indexOf(
        'Future<List<_PreparedUploadFile>> _collectWebUploadItems',
      ),
    );

    expect(filePickerStart, greaterThanOrEqualTo(0));
    expect(folderPickerStart, greaterThanOrEqualTo(0));
    expect(preparedLengthStart, greaterThan(filePickerStart));
    expect(
      filePickerSource.indexOf('_collectWebUploadItems'),
      lessThan(filePickerSource.indexOf('_ensureWebUploadEncryptionReady')),
    );
    expect(
      folderPickerSource.indexOf('_collectWebFolderUploadItems'),
      lessThan(folderPickerSource.indexOf('_ensureWebUploadEncryptionReady')),
    );
    expect(
      filePickerSource.indexOf('_ensureWebUploadEncryptionReady'),
      lessThan(filePickerSource.indexOf('_handlePreparedUpload')),
    );
    expect(
      folderPickerSource.indexOf('_ensureWebUploadEncryptionReady'),
      lessThan(folderPickerSource.indexOf('_handlePreparedUpload')),
    );
    expect(
      workspaceSource,
      contains('no bytes are read until encryption is ready'),
    );
    expect(workspaceSource, contains('return mounted && key != null;'));
  });

  test('upload failure boundary does not forward typed exception messages', () {
    final workspaceSource = File(
      'lib/src/home/workspace_home_page.dart',
    ).readAsStringSync();
    final exceptionSource = File(
      'lib/src/home/workspace_home_page_supporting_types.dart',
    ).readAsStringSync();

    expect(
      workspaceSource,
      isNot(
        contains(
          'if (error is WasabiStorageException) {\n      return error.message;',
        ),
      ),
    );
    expect(
      workspaceSource,
      isNot(
        contains(
          'if (error is UploadMetadataException) {\n      return error.message;',
        ),
      ),
    );
    expect(
      exceptionSource,
      contains("String toString() => 'EncryptionPasswordException';"),
    );
  });
}
