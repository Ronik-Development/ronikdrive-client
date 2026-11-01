import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'upload_coordinator.dart';

/// Abort the request itself on cancellation or timeout, without closing a client
/// shared by unrelated downloads and uploads.
Future<String?> putUploadPart({
  required http.Client client,
  required Uri url,
  required Uint8List bytes,
  required Future<void> abortSignal,
  Map<String, String> headers = const {},
  Duration timeout = const Duration(minutes: 10),
}) async {
  final abort = Completer<void>();
  var timedOut = false;
  void stop() {
    if (!abort.isCompleted) abort.complete();
  }

  unawaited(abortSignal.then((_) => stop()));
  final timer = Timer(timeout, () {
    timedOut = true;
    stop();
  });
  try {
    final request =
        http.AbortableRequest('PUT', url, abortTrigger: abort.future)
          ..headers.addAll(headers)
          ..headers['Content-Type'] = 'application/octet-stream'
          ..bodyBytes = bytes;
    final response = await client.send(request);
    await response.stream.drain<void>();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const UploadFailure('unavailable');
    }
    return response.headers['etag'];
  } on http.RequestAbortedException {
    throw UploadFailure(timedOut ? 'unavailable' : 'canceled');
  } finally {
    timer.cancel();
  }
}
