import 'dart:math';
import 'dart:typed_data';

/// Traffic analysis defense utility that pads ciphertext payloads into discrete
/// size buckets to prevent passive observers from fingerprinting file contents
/// based on exact byte lengths.
class PayloadPadding {
  PayloadPadding._();

  /// Default minimum bucket size is 64 KiB.
  static const int defaultMinBucketBytes = 64 * 1024;

  /// Standard bucket tiers (in bytes) for discrete power-of-two padding.
  static const List<int> standardBucketTiers = <int>[
    64 * 1024, // 64 KiB
    256 * 1024, // 256 KiB
    1024 * 1024, // 1 MiB
    4 * 1024 * 1024, // 4 MiB
    16 * 1024 * 1024, // 16 MiB
  ];

  /// Calculates the target padded container size for a given [payloadLength].
  static int calculatePaddedBucketSize(
    int payloadLength, {
    int minBucketBytes = defaultMinBucketBytes,
  }) {
    // Total raw needed = 4 bytes length header + payload
    final totalNeeded = 4 + payloadLength;
    for (final tier in standardBucketTiers) {
      if (tier >= minBucketBytes && totalNeeded <= tier) {
        return tier;
      }
    }
    // For objects larger than 16 MiB, pad to the next 4 MiB boundary
    const largeStep = 4 * 1024 * 1024;
    return ((totalNeeded + largeStep - 1) ~/ largeStep) * largeStep;
  }

  /// Pads [payload] into a discrete size bucket.
  ///
  /// Header: 4-byte Big-Endian unsigned integer representing original payload size.
  /// Followed by: exact payload bytes.
  /// Followed by: padding bytes up to target container size.
  static Uint8List padPayload(
    Uint8List payload, {
    int minBucketBytes = defaultMinBucketBytes,
    Random? random,
  }) {
    final targetSize = calculatePaddedBucketSize(
      payload.length,
      minBucketBytes: minBucketBytes,
    );

    final padded = Uint8List(targetSize);
    final byteData = ByteData.sublistView(padded);

    // 4-byte length header
    byteData.setUint32(0, payload.length, Endian.big);

    // Copy payload
    padded.setRange(4, 4 + payload.length, payload);

    // Fill remaining bytes with deterministic or random padding
    final paddingStart = 4 + payload.length;
    final paddingLength = targetSize - paddingStart;
    if (paddingLength > 0) {
      final rng = random ?? Random();
      for (var i = 0; i < paddingLength; i++) {
        padded[paddingStart + i] = rng.nextInt(256);
      }
    }

    return padded;
  }

  /// Unpads a previously padded payload and verifies its structure.
  ///
  /// Throws [FormatException] if the buffer is malformed or corrupted.
  static Uint8List unpadPayload(Uint8List paddedPayload) {
    if (paddedPayload.length < 4) {
      throw const FormatException(
        'Invalid padded payload: buffer is shorter than minimum header size.',
      );
    }

    final byteData = ByteData.sublistView(paddedPayload);
    final originalLength = byteData.getUint32(0, Endian.big);

    if (originalLength + 4 > paddedPayload.length) {
      throw FormatException(
        'Corrupted padded payload: expected $originalLength bytes but total '
        'container size is ${paddedPayload.length}.',
      );
    }

    final result = Uint8List(originalLength);
    result.setRange(0, originalLength, paddedPayload, 4);
    return result;
  }
}
