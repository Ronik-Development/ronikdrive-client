const int webUploadReadChunkBytes = 1024 * 1024;

typedef WebUploadByteRange = ({int start, int endExclusive});

/// Splits a browser File/Blob read into bounded ranges.
///
/// Browser selections can be many gigabytes. Reading each File with one
/// `arrayBuffer()` duplicates the complete plaintext in memory before
/// encryption begins. The web adapter uses these ranges to request one bounded
/// Blob slice at a time, and can reopen the same source for a thumbnail or an
/// upload retry without retaining a full plaintext copy.
Iterable<WebUploadByteRange> webUploadByteRanges({
  required int length,
  int start = 0,
  int? endExclusive,
  int chunkBytes = webUploadReadChunkBytes,
}) sync* {
  if (length <= 0 || chunkBytes <= 0) {
    return;
  }
  final safeStart = start.clamp(0, length).toInt();
  final safeEnd = (endExclusive ?? length).clamp(safeStart, length).toInt();
  for (var offset = safeStart; offset < safeEnd; offset += chunkBytes) {
    yield (
      start: offset,
      endExclusive: (offset + chunkBytes).clamp(offset, safeEnd).toInt(),
    );
  }
}
