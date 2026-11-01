class PickedWebFolderFile {
  const PickedWebFolderFile({
    required this.sizeBytes,
    required this.name,
    required this.relativePath,
    this.mimeType,
  });

  final int sizeBytes;
  final String name;
  final String relativePath;
  final String? mimeType;

  Stream<List<int>> openRead([int start = 0, int? endExclusive]) =>
      const Stream<List<int>>.empty();
}

Future<List<PickedWebFolderFile>> pickWebFolderUploadFiles() async {
  return const <PickedWebFolderFile>[];
}

Future<List<PickedWebFolderFile>> pickWebUploadFiles({
  String accept = '',
  bool allowMultiple = true,
}) async {
  return const <PickedWebFolderFile>[];
}
