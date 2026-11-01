import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:cloud_storage/src/storage/image_thumbnail_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('encryptedUploadCompletionMessage', () {
    test('reports an ordinary successful source upload concisely', () {
      expect(
        encryptedUploadCompletionMessage(uploadedCount: 1),
        'Uploaded 1 item successfully.',
      );
      expect(
        encryptedUploadCompletionMessage(uploadedCount: 3),
        'Uploaded 3 items successfully.',
      );
    });

    test('reassures users when optional image previews need retrying', () {
      final message = encryptedUploadCompletionMessage(
        uploadedCount: 2,
        previewRetryCount: 2,
      );

      expect(message, contains('2 image previews will retry automatically'));
      expect(message, contains('encrypted originals are safe'));
      expect(message, isNot(contains('filename')));
      expect(message, isNot(contains('object')));
    });

    test('distinguishes recoverable metadata finalization from failure', () {
      expect(
        encryptedUploadFinalizationPendingMessage(pendingCount: 1),
        contains('1 encrypted upload has reached storage'),
      );
      expect(
        encryptedUploadFinalizationPendingMessage(pendingCount: 2),
        contains('2 encrypted uploads have reached storage'),
      );
      expect(
        encryptedUploadFinalizationPendingMessage(pendingCount: 2),
        contains('retry automatically'),
      );
      expect(
        encryptedUploadFinalizationPendingMessage(pendingCount: 2),
        isNot(contains('failed')),
      );
    });
  });

  group('uploadSourceThenOptionalDerivative', () {
    test('always finishes the encrypted source before preview work', () async {
      final events = <String>[];

      final result = await uploadSourceThenOptionalDerivative<String>(
        uploadSource: () async {
          events.add('source-start');
          await Future<void>.delayed(Duration.zero);
          events.add('source-complete');
        },
        afterSourceUpload: () async {
          events.add('source-recorded');
        },
        uploadDerivative: () async {
          events.add('preview-start');
          return 'preview';
        },
      );

      expect(result, 'preview');
      expect(events, <String>[
        'source-start',
        'source-complete',
        'source-recorded',
        'preview-start',
      ]);
    });

    test('preview failure cannot fail a completed source upload', () async {
      Object? reportedError;

      final result = await uploadSourceThenOptionalDerivative<String>(
        uploadSource: () async {},
        uploadDerivative: () async => throw StateError('decoder failed'),
        onDerivativeError: (error, _) {
          reportedError = error;
        },
      );

      expect(result, isNull);
      expect(reportedError, isA<StateError>());
    });

    test(
      'a stalled preview cannot hold a completed source upload open',
      () async {
        Object? reportedError;

        final result = await uploadSourceThenOptionalDerivative<String>(
          uploadSource: () async {},
          uploadDerivative: () => Completer<String?>().future,
          derivativeTimeout: const Duration(milliseconds: 5),
          onDerivativeError: (error, _) {
            reportedError = error;
          },
        );

        expect(result, isNull);
        expect(reportedError, isA<TimeoutException>());
      },
    );

    test('source failure propagates and skips preview work', () async {
      var previewStarted = false;

      await expectLater(
        uploadSourceThenOptionalDerivative<String>(
          uploadSource: () async => throw StateError('source failed'),
          uploadDerivative: () async {
            previewStarted = true;
            return 'preview';
          },
        ),
        throwsStateError,
      );
      expect(previewStarted, isFalse);
    });
  });

  group('ImageThumbnailPolicy', () {
    test('accepts ordinary images and rejects empty or oversized sources', () {
      expect(ImageThumbnailPolicy.allowsSourceBytes(1), isTrue);
      expect(
        ImageThumbnailPolicy.allowsSourceBytes(imageThumbnailMaxSourceBytes),
        isTrue,
      );
      expect(ImageThumbnailPolicy.allowsSourceBytes(0), isFalse);
      expect(
        ImageThumbnailPolicy.allowsSourceBytes(
          imageThumbnailMaxSourceBytes + 1,
        ),
        isFalse,
      );
    });

    test('rejects invalid dimensions and decompression-bomb dimensions', () {
      expect(ImageThumbnailPolicy.allowsDimensions(4032, 3024), isTrue);
      expect(ImageThumbnailPolicy.allowsDimensions(0, 100), isFalse);
      expect(ImageThumbnailPolicy.allowsDimensions(100, -1), isFalse);
      expect(ImageThumbnailPolicy.allowsDimensions(10000, 10000), isTrue);
      expect(ImageThumbnailPolicy.allowsDimensions(10001, 10000), isFalse);
    });

    test('preserves aspect ratio and never upscales', () {
      expect(ImageThumbnailPolicy.targetDimensions(800, 400), (
        width: 256,
        height: 128,
      ));
      expect(ImageThumbnailPolicy.targetDimensions(400, 800), (
        width: 128,
        height: 256,
      ));
      expect(ImageThumbnailPolicy.targetDimensions(120, 80), (
        width: 120,
        height: 80,
      ));
    });
  });

  group('ImageThumbnailRetryPolicy', () {
    test('keeps transient image recovery automatic and bounded', () {
      for (
        var completed = 0;
        completed < ImageThumbnailRetryPolicy.maxAutomaticRetries;
        completed += 1
      ) {
        expect(
          ImageThumbnailRetryPolicy.canRetryAutomatically(
            isImageLike: true,
            completedRetries: completed,
          ),
          isTrue,
        );
      }
      expect(
        ImageThumbnailRetryPolicy.canRetryAutomatically(
          isImageLike: true,
          completedRetries: ImageThumbnailRetryPolicy.maxAutomaticRetries,
        ),
        isFalse,
      );
      expect(
        ImageThumbnailRetryPolicy.canRetryAutomatically(
          isImageLike: false,
          completedRetries: 0,
        ),
        isFalse,
      );
    });

    test('uses increasing bounded retry delays', () {
      expect(
        ImageThumbnailRetryPolicy.delayBeforeNextRetry(0),
        const Duration(seconds: 2),
      );
      expect(
        ImageThumbnailRetryPolicy.delayBeforeNextRetry(4),
        const Duration(seconds: 10),
      );
      expect(
        ImageThumbnailRetryPolicy.delayBeforeNextRetry(99),
        const Duration(seconds: 10),
      );
    });
  });

  group('readBoundedImageSource', () {
    test(
      'does not open a source whose declared size exceeds the budget',
      () async {
        var opened = false;

        final bytes = await readBoundedImageSource(
          sourceLength: () async => 5,
          openRead: (_) {
            opened = true;
            return Stream<List<int>>.value(<int>[1, 2, 3, 4, 5]);
          },
          maxSourceBytes: 4,
        );

        expect(bytes, isNull);
        expect(opened, isFalse);
      },
    );

    test('rejects a source that grows while it is being streamed', () async {
      final requestedEnds = <int>[];

      final bytes = await readBoundedImageSource(
        sourceLength: () async => 3,
        openRead: (endExclusive) {
          requestedEnds.add(endExclusive);
          return Stream<List<int>>.fromIterable(<List<int>>[
            <int>[1, 2],
            <int>[3, 4, 5],
          ]);
        },
        maxSourceBytes: 4,
      );

      expect(bytes, isNull);
      expect(requestedEnds, <int>[5]);
    });

    test('returns an in-budget streamed source unchanged', () async {
      final bytes = await readBoundedImageSource(
        sourceLength: () async => 4,
        openRead: (_) => Stream<List<int>>.fromIterable(<List<int>>[
          <int>[1, 2],
          <int>[3, 4],
        ]),
        maxSourceBytes: 4,
      );

      expect(bytes, orderedEquals(<int>[1, 2, 3, 4]));
    });
  });

  group('captureBoundedImageUploadSource', () {
    test('captures the source once for upload and preview reuse', () async {
      var opened = 0;
      final requestedEnds = <int>[];

      final bytes = await captureBoundedImageUploadSource(
        expectedLength: 4,
        sourceLength: () async => 4,
        openRead: (endExclusive) {
          opened += 1;
          requestedEnds.add(endExclusive);
          return Stream<List<int>>.fromIterable(<List<int>>[
            <int>[1, 2],
            <int>[3, 4],
          ]);
        },
        maxSourceBytes: 4,
      );

      expect(bytes, orderedEquals(<int>[1, 2, 3, 4]));
      expect(opened, 1);
      expect(requestedEnds, <int>[5]);
    });

    test('rejects a declared length that changed before capture', () async {
      var opened = false;

      final bytes = await captureBoundedImageUploadSource(
        expectedLength: 4,
        sourceLength: () async => 3,
        openRead: (_) {
          opened = true;
          return Stream<List<int>>.value(<int>[1, 2, 3, 4]);
        },
        maxSourceBytes: 4,
      );

      expect(bytes, isNull);
      expect(opened, isFalse);
    });

    test('rejects streamed bytes that differ from prepared length', () async {
      final bytes = await captureBoundedImageUploadSource(
        expectedLength: 4,
        sourceLength: () async => 4,
        openRead: (_) => Stream<List<int>>.value(<int>[1, 2, 3]),
        maxSourceBytes: 4,
      );

      expect(bytes, isNull);
    });

    test('does not open an upload source outside the preview budget', () async {
      var opened = false;

      final bytes = await captureBoundedImageUploadSource(
        expectedLength: 5,
        sourceLength: () async => 5,
        openRead: (_) {
          opened = true;
          return Stream<List<int>>.value(<int>[1, 2, 3, 4, 5]);
        },
        maxSourceBytes: 4,
      );

      expect(bytes, isNull);
      expect(opened, isFalse);
    });
  });

  group('normalizeStoredImageThumbnail', () {
    test('bounds and normalizes a stored preview locally', () async {
      final sourceImage = img.Image(width: 64, height: 32);
      img.fill(sourceImage, color: img.ColorRgb8(44, 96, 180));
      final stored = Uint8List.fromList(img.encodeJpg(sourceImage));

      final normalized = await normalizeStoredImageThumbnail(
        Stream<List<int>>.fromIterable(<List<int>>[
          stored.sublist(0, stored.length ~/ 2),
          stored.sublist(stored.length ~/ 2),
        ]),
        maxStoredBytes: stored.length,
      );

      expect(normalized, isNotNull);
      expect(
        normalized!.sublist(0, 8),
        orderedEquals(<int>[137, 80, 78, 71, 13, 10, 26, 10]),
      );
      final decoded = img.decodePng(normalized);
      expect(decoded, isNotNull);
      expect(decoded!.width, 64);
      expect(decoded.height, 32);
    });

    test('rejects oversized, empty, corrupt, and failing candidates', () async {
      expect(
        await normalizeStoredImageThumbnail(
          Stream<List<int>>.fromIterable(<List<int>>[
            <int>[1, 2, 3, 4],
            <int>[5],
          ]),
          maxStoredBytes: 4,
        ),
        isNull,
      );
      expect(
        await normalizeStoredImageThumbnail(const Stream<List<int>>.empty()),
        isNull,
      );
      expect(
        await normalizeStoredImageThumbnail(
          Stream<List<int>>.value(<int>[0, 1, 2, 3]),
        ),
        isNull,
      );
      expect(
        await normalizeStoredImageThumbnail(
          Stream<List<int>>.error(StateError('provider detail')),
        ),
        isNull,
      );
    });
  });

  group('generateBoundedImageThumbnail', () {
    test('returns null for malformed image data', () async {
      final thumbnail = await generateBoundedImageThumbnail(
        Uint8List.fromList(<int>[0, 1, 2, 3, 4, 5]),
      );

      expect(thumbnail, isNull);
    });

    test('creates a bounded PNG without mutating the source', () async {
      final sourceImage = img.Image(width: 800, height: 400);
      img.fill(sourceImage, color: img.ColorRgb8(18, 72, 140));
      final source = Uint8List.fromList(img.encodePng(sourceImage));
      final original = Uint8List.fromList(source);

      final thumbnail = await generateBoundedImageThumbnail(source);

      expect(source, orderedEquals(original));
      expect(thumbnail, isNotNull);
      expect(
        thumbnail!.sublist(0, 8),
        orderedEquals(<int>[137, 80, 78, 71, 13, 10, 26, 10]),
      );
      final decoded = img.decodePng(thumbnail);
      expect(decoded, isNotNull);
      expect(decoded!.width, 256);
      expect(decoded.height, 128);
      expect(imageThumbnailContentType, 'image/png');
    });
  });
}
