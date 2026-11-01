import 'dart:typed_data';

/// Cryptographic memory protection utilities for sanitizing sensitive in-memory
/// key material, plaintext buffers, and passphrases.
class MemoryProtection {
  MemoryProtection._();

  /// Overwrites a [Uint8List] buffer with zeroes in-place to prevent key leakage
  /// in memory dumps, core dumps, or page swapping.
  static void secureZero(Uint8List? buffer) {
    if (buffer == null || buffer.isEmpty) {
      return;
    }
    buffer.fillRange(0, buffer.length, 0);
  }

  /// Overwrites a generic integer list buffer with zeroes in-place.
  static void secureZeroList(List<int>? buffer) {
    if (buffer == null || buffer.isEmpty) {
      return;
    }
    for (var i = 0; i < buffer.length; i++) {
      buffer[i] = 0;
    }
  }

  /// Executes [action] with a sensitive [buffer] and guarantees that the buffer
  /// is securely zeroed in a `finally` block even if an exception occurs.
  static Future<T> withTemporaryKeyBuffer<T>(
    Uint8List buffer,
    Future<T> Function(Uint8List buffer) action,
  ) async {
    try {
      return await action(buffer);
    } finally {
      secureZero(buffer);
    }
  }

  /// Executes synchronous [action] with a sensitive [buffer] and guarantees
  /// zeroing upon completion or error.
  static T withTemporaryKeyBufferSync<T>(
    Uint8List buffer,
    T Function(Uint8List buffer) action,
  ) {
    try {
      return action(buffer);
    } finally {
      secureZero(buffer);
    }
  }

  /// Performs a constant-time comparison of two byte lists to prevent timing
  /// side-channel attacks during cryptographic tag or MAC verification.
  static bool constantTimeCompare(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}
