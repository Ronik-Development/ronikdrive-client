/// A single HTTP byte range over an already authenticated plaintext buffer.
/// Parsing never authorizes partial ciphertext decryption.
class HttpByteRange {
  const HttpByteRange(this.start, this.end);
  final int start, end;
  int get length => end - start + 1;

  static HttpByteRange? parse(String value, int size) {
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(value.trim());
    if (match == null || size <= 0) return null;
    final first = match[1]!;
    final last = match[2]!;
    if (first.isEmpty) {
      final suffix = int.tryParse(last);
      if (suffix == null || suffix <= 0) return null;
      return HttpByteRange(suffix >= size ? 0 : size - suffix, size - 1);
    }
    final start = int.tryParse(first);
    final end = last.isEmpty ? size - 1 : int.tryParse(last);
    if (start == null || end == null || start >= size || end < start) {
      return null;
    }
    return HttpByteRange(start, end >= size ? size - 1 : end);
  }
}
