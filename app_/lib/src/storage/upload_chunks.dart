import 'dart:typed_data';

/// Bounded views avoid asking encryption to process an entire picker buffer in
/// one UI turn. Upstream producers still need to provide streaming sources.
Stream<List<int>> boundedUploadChunks(Stream<List<int>> source) async* {
  const maximum = 64 * 1024;
  await for (final chunk in source) {
    for (var start = 0; start < chunk.length; start += maximum) {
      final end = (start + maximum).clamp(0, chunk.length);
      yield chunk is Uint8List
          ? Uint8List.sublistView(chunk, start, end)
          : chunk.sublist(start, end);
      await Future<void>.delayed(Duration.zero);
    }
  }
}
