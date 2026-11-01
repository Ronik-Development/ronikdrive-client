import 'dart:async';
import 'package:http/http.dart' as http;

/// Keeps provider data streamed and cancels its transport when the consumer
/// stops. The listing length is checked before and during both verified reads.
Stream<List<int>> readRemoteFileStream({
  required http.Client client,
  required String method,
  required Uri uri,
  required Map<String, String> headers,
  required int? expectedLength,
  int maximumLength = 8 * 1024 * 1024 * 10000,
  Duration idleTimeout = const Duration(minutes: 2),
}) async* {
  final abort = Completer<void>();
  try {
    final request = http.AbortableRequest(
      method,
      uri,
      abortTrigger: abort.future,
    )..headers.addAll(headers);
    final response = await client.send(request).timeout(idleTimeout);
    if (response.statusCode != 200 ||
        response.contentLength != null &&
            (response.contentLength! > maximumLength ||
                expectedLength != null &&
                    response.contentLength != expectedLength)) {
      throw StateError('The remote file is unavailable or has changed.');
    }
    var length = 0;
    await for (final chunk in response.stream.timeout(idleTimeout)) {
      length += chunk.length;
      if (length > maximumLength ||
          expectedLength != null && length > expectedLength) {
        throw StateError('The remote file has changed.');
      }
      yield chunk;
    }
    if (expectedLength != null && length != expectedLength) {
      throw StateError('The remote file has changed.');
    }
  } finally {
    if (!abort.isCompleted) abort.complete();
  }
}
