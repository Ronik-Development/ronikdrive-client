import 'file_downloader_stub.dart'
    if (dart.library.js_interop) 'file_downloader_web.dart';

Future<void> downloadFile(List<int> bytes, String fileName) =>
    downloadFileImpl(bytes, fileName);
