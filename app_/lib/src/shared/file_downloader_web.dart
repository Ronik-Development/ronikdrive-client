import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'dart:js_interop';

Future<void> downloadFileImpl(List<int> bytes, String fileName) async {
  final uint8List = Uint8List.fromList(bytes);
  final blob = web.Blob([uint8List.toJS].toJS);
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = url;
  anchor.download = fileName;
  anchor.click();
  web.URL.revokeObjectURL(url);
}
