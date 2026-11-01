import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'web_upload_stream_policy.dart';

class PickedWebFolderFile {
  PickedWebFolderFile._({
    required web.File browserFile,
    required this.name,
    required this.relativePath,
    this.mimeType,
  }) : _browserFile = browserFile,
       sizeBytes = browserFile.size;

  final web.File _browserFile;
  final int sizeBytes;
  final String name;
  final String relativePath;
  final String? mimeType;

  Stream<List<int>> openRead([int start = 0, int? endExclusive]) async* {
    for (final range in webUploadByteRanges(
      length: sizeBytes,
      start: start,
      endExclusive: endExclusive,
    )) {
      final slice = _browserFile.slice(range.start, range.endExclusive);
      final buffer = await slice.arrayBuffer().toDart;
      final bytes = buffer.toDart.asUint8List();
      if (bytes.isNotEmpty) {
        yield bytes;
      }
    }
  }
}

Future<List<PickedWebFolderFile>> pickWebFolderUploadFiles() async {
  return _pickWebUploadFiles(allowDirectory: true);
}

Future<List<PickedWebFolderFile>> pickWebUploadFiles({
  String accept = '',
  bool allowMultiple = true,
}) async {
  return _pickWebUploadFiles(
    allowDirectory: false,
    accept: accept,
    allowMultiple: allowMultiple,
  );
}

Future<List<PickedWebFolderFile>> _pickWebUploadFiles({
  required bool allowDirectory,
  String accept = '',
  bool allowMultiple = true,
}) async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = allowMultiple;
  if (allowDirectory) {
    input.webkitdirectory = true;
  }
  final trimmedAccept = accept.trim();
  if (trimmedAccept.isNotEmpty) {
    input.accept = trimmedAccept;
  }
  input.style.display = 'none';
  web.document.body?.appendChild(input);

  final completer = Completer<List<PickedWebFolderFile>>();
  StreamSubscription<web.Event>? changeSubscription;
  StreamSubscription<web.Event>? cancelSubscription;

  Future<void> cleanup() async {
    await changeSubscription?.cancel();
    await cancelSubscription?.cancel();
    input.remove();
  }

  Future<void> completeFromSelection() async {
    try {
      final files = input.files;
      if (files == null || files.length == 0) {
        if (!completer.isCompleted) {
          completer.complete(const <PickedWebFolderFile>[]);
        }
        return;
      }

      final picked = <PickedWebFolderFile>[];
      for (var index = 0; index < files.length; index += 1) {
        final browserFile = files.item(index);
        if (browserFile == null) {
          continue;
        }
        picked.add(
          PickedWebFolderFile._(
            browserFile: browserFile,
            name: browserFile.name,
            relativePath: browserFile.webkitRelativePath,
            mimeType: browserFile.type.trim().isEmpty
                ? null
                : browserFile.type.trim(),
          ),
        );
      }

      if (!completer.isCompleted) {
        completer.complete(picked);
      }
    } catch (error, stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    } finally {
      await cleanup();
    }
  }

  changeSubscription = input.onChange.listen((_) {
    unawaited(completeFromSelection());
  });
  cancelSubscription = web.EventStreamProviders.cancelEvent
      .forElement(input)
      .listen((_) {
        if (!completer.isCompleted) {
          completer.complete(const <PickedWebFolderFile>[]);
        }
        unawaited(cleanup());
      });

  input.click();
  return completer.future.timeout(
    const Duration(minutes: 5),
    onTimeout: () {
      unawaited(cleanup());
      return const <PickedWebFolderFile>[];
    },
  );
}
