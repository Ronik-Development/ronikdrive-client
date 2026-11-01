import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

const int imageThumbnailMaxSourceBytes = 24 * 1024 * 1024;
const int imageThumbnailMaxSourcePixels = 100 * 1000 * 1000;
const int imageThumbnailMaxEdge = 256;
const int imageThumbnailMaxStoredBytes = 2 * 1024 * 1024;
const String imageThumbnailContentType = 'image/png';
const Duration imageThumbnailDerivativeTimeout = Duration(seconds: 20);

/// Keeps transient preview work distinct from a user-actionable failure.
///
/// A newly finalized image can become visible before its optional encrypted
/// preview object is readable through every listener and storage path. The UI
/// should continue its bounded automatic recovery during that window instead
/// of immediately presenting a manual Retry action.
abstract final class ImageThumbnailRetryPolicy {
  static const int maxAutomaticRetries = 5;

  static bool canRetryAutomatically({
    required bool isImageLike,
    required int completedRetries,
  }) {
    return isImageLike &&
        completedRetries >= 0 &&
        completedRetries < maxAutomaticRetries;
  }

  static Duration delayBeforeNextRetry(int completedRetries) {
    final nextAttempt = (completedRetries + 1)
        .clamp(1, maxAutomaticRetries)
        .toInt();
    return Duration(seconds: (2 * nextAttempt).clamp(2, 12).toInt());
  }
}

/// Builds upload feedback that distinguishes a safe encrypted source from an
/// optional preview that still needs to retry.
String encryptedUploadCompletionMessage({
  required int uploadedCount,
  int previewRetryCount = 0,
}) {
  final safeUploadedCount = uploadedCount < 0 ? 0 : uploadedCount;
  final safeRetryCount = previewRetryCount.clamp(0, safeUploadedCount);
  final itemLabel = safeUploadedCount == 1 ? 'item' : 'items';
  final base = 'Uploaded $safeUploadedCount $itemLabel successfully.';
  if (safeRetryCount == 0) {
    return base;
  }
  final previewLabel = safeRetryCount == 1 ? 'preview' : 'previews';
  final originalLabel = safeRetryCount == 1 ? 'original is' : 'originals are';
  return '$base $safeRetryCount image $previewLabel will retry automatically; '
      'the encrypted $originalLabel safe.';
}

String encryptedUploadFinalizationPendingMessage({required int pendingCount}) {
  final safeCount = pendingCount < 0 ? 0 : pendingCount;
  final itemLabel = safeCount == 1 ? 'upload' : 'uploads';
  final state = safeCount == 1
      ? 'has reached storage and is waiting'
      : 'have reached storage and are waiting';
  return '$safeCount encrypted $itemLabel $state for private metadata '
      'finalization. RonikCloud will retry automatically; keep the app open '
      'when possible.';
}

/// Completes the required encrypted source transfer before attempting an
/// optional client-side derivative such as a thumbnail.
///
/// Source failures remain fatal. Derivative failures are reported through
/// [onDerivativeError] and return `null`, so preview work can never turn a
/// successful source upload into a failed file upload.
Future<T?> uploadSourceThenOptionalDerivative<T>({
  required Future<void> Function() uploadSource,
  Future<void> Function()? afterSourceUpload,
  Future<T?> Function()? uploadDerivative,
  Duration? derivativeTimeout,
  void Function(Object error, StackTrace stackTrace)? onDerivativeError,
}) async {
  await uploadSource();
  if (afterSourceUpload != null) {
    await afterSourceUpload();
  }
  if (uploadDerivative == null) {
    return null;
  }
  try {
    final derivative = uploadDerivative();
    return await (derivativeTimeout == null
        ? derivative
        : derivative.timeout(derivativeTimeout));
  } catch (error, stackTrace) {
    onDerivativeError?.call(error, stackTrace);
    return null;
  }
}

/// Resource limits applied before a photo is decoded for a workspace preview.
///
/// Preview generation is optional. A source outside these limits is uploaded
/// normally without a thumbnail so an unusually large or malformed image can
/// never block the encrypted original upload.
abstract final class ImageThumbnailPolicy {
  static bool allowsSourceBytes(int byteLength) {
    return byteLength > 0 && byteLength <= imageThumbnailMaxSourceBytes;
  }

  static bool allowsDimensions(int width, int height) {
    if (width <= 0 || height <= 0) {
      return false;
    }
    return width * height <= imageThumbnailMaxSourcePixels;
  }

  static ({int width, int height}) targetDimensions(
    int width,
    int height, {
    int maxEdge = imageThumbnailMaxEdge,
  }) {
    if (width <= 0 || height <= 0 || maxEdge <= 0) {
      return (width: 0, height: 0);
    }
    final longestEdge = width > height ? width : height;
    if (longestEdge <= maxEdge) {
      return (width: width, height: height);
    }
    final scale = maxEdge / longestEdge;
    return (
      width: (width * scale).round().clamp(1, maxEdge),
      height: (height * scale).round().clamp(1, maxEdge),
    );
  }
}

/// Reads at most [maxSourceBytes] from an image source.
///
/// The declared length is checked before opening the stream. The streamed
/// length is checked again because a watched file can grow between `stat` and
/// `openRead`. Returning `null` is intentional: thumbnails are optional and a
/// source outside the preview budget must not block its encrypted original.
Future<Uint8List?> readBoundedImageSource({
  required Future<int> Function() sourceLength,
  required Stream<List<int>> Function(int endExclusive) openRead,
  int maxSourceBytes = imageThumbnailMaxSourceBytes,
}) async {
  if (maxSourceBytes <= 0) {
    return null;
  }

  try {
    final declaredLength = await sourceLength();
    if (declaredLength <= 0 || declaredLength > maxSourceBytes) {
      return null;
    }

    final bytes = BytesBuilder(copy: false);
    await for (final chunk in openRead(maxSourceBytes + 1)) {
      if (chunk.isEmpty) {
        continue;
      }
      if (bytes.length + chunk.length > maxSourceBytes) {
        return null;
      }
      bytes.add(chunk);
    }

    final result = bytes.takeBytes();
    return result.isEmpty ? null : result;
  } catch (_) {
    return null;
  }
}

/// Reads and locally validates a stored encrypted preview derivative.
///
/// Preview objects are expected to be small, but storage is still an untrusted
/// boundary. The byte ceiling is enforced while streaming so a malformed or
/// unexpectedly large object cannot be accumulated in memory. Valid image
/// bytes are decoded and re-encoded into the current bounded PNG contract; an
/// empty, oversized, corrupt, or unsupported candidate returns `null` so the
/// caller can rebuild it from the authenticated encrypted original.
Future<Uint8List?> normalizeStoredImageThumbnail(
  Stream<List<int>> source, {
  int maxStoredBytes = imageThumbnailMaxStoredBytes,
  Duration timeout = const Duration(seconds: 8),
}) async {
  if (maxStoredBytes <= 0) {
    return null;
  }
  try {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in source) {
      if (chunk.isEmpty) {
        continue;
      }
      if (bytes.length + chunk.length > maxStoredBytes) {
        return null;
      }
      bytes.add(chunk);
    }
    final candidate = bytes.takeBytes();
    if (candidate.isEmpty) {
      return null;
    }
    return generateBoundedImageThumbnail(candidate, timeout: timeout);
  } catch (_) {
    return null;
  }
}

/// Captures the exact bytes that will be used for both an encrypted image
/// upload and its optional preview.
///
/// A changing file may still fit within the preview budget while no longer
/// matching the length that the upload was prepared with. Rejecting that
/// snapshot keeps the upload contract honest: callers can fall back to the
/// ordinary source stream and omit the preview until it can be rebuilt from
/// the encrypted remote original.
Future<Uint8List?> captureBoundedImageUploadSource({
  required int expectedLength,
  required Future<int> Function() sourceLength,
  required Stream<List<int>> Function(int endExclusive) openRead,
  int maxSourceBytes = imageThumbnailMaxSourceBytes,
}) async {
  if (expectedLength <= 0 || expectedLength > maxSourceBytes) {
    return null;
  }
  int declaredLength;
  try {
    declaredLength = await sourceLength();
  } catch (_) {
    return null;
  }
  if (declaredLength != expectedLength) {
    return null;
  }
  final sourceBytes = await readBoundedImageSource(
    sourceLength: () async => declaredLength,
    openRead: openRead,
    maxSourceBytes: maxSourceBytes,
  );
  if (sourceBytes == null || sourceBytes.length != expectedLength) {
    return null;
  }
  return sourceBytes;
}

/// Reads a possibly changing source within the preview budget and creates a
/// bounded thumbnail from it.
Future<Uint8List?> generateBoundedImageThumbnailFromSource({
  required Future<int> Function() sourceLength,
  required Stream<List<int>> Function(int endExclusive) openRead,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final sourceBytes = await readBoundedImageSource(
    sourceLength: sourceLength,
    openRead: openRead,
  );
  if (sourceBytes == null) {
    return null;
  }
  return generateBoundedImageThumbnail(sourceBytes, timeout: timeout);
}

/// Creates a bounded PNG preview using Flutter's asynchronous image codec.
///
/// Unlike `image.decodeImage`, the codec receives target dimensions before it
/// decodes pixels. This avoids materializing a full-resolution Dart image on
/// the UI isolate, especially important for high-resolution photos on web.
Future<Uint8List?> generateBoundedImageThumbnail(
  Uint8List sourceBytes, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  if (!ImageThumbnailPolicy.allowsSourceBytes(sourceBytes.length)) {
    return null;
  }

  try {
    return await _generateBoundedImageThumbnail(sourceBytes).timeout(timeout);
  } catch (_) {
    return null;
  }
}

Future<Uint8List?> _generateBoundedImageThumbnail(Uint8List sourceBytes) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? decodedImage;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(sourceBytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (!ImageThumbnailPolicy.allowsDimensions(
      descriptor.width,
      descriptor.height,
    )) {
      return null;
    }

    final target = ImageThumbnailPolicy.targetDimensions(
      descriptor.width,
      descriptor.height,
    );
    codec = await descriptor.instantiateCodec(
      targetWidth: target.width,
      targetHeight: target.height,
    );
    final frame = await codec.getNextFrame();
    decodedImage = frame.image;
    final encoded = await decodedImage.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (encoded == null || encoded.lengthInBytes == 0) {
      return null;
    }
    return encoded.buffer.asUint8List(
      encoded.offsetInBytes,
      encoded.lengthInBytes,
    );
  } finally {
    decodedImage?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}
