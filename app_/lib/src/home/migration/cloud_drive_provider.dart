import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Representation of a remote entry returned by a cloud drive provider.
abstract class RemoteEntry {
  const RemoteEntry({required this.id, required this.name});

  final String id;
  final String name;

  bool get isFolder;
}

class RemoteFolderEntry extends RemoteEntry {
  const RemoteFolderEntry({
    required super.id,
    required super.name,
    this.pathSegments = const <String>[],
    this.remotePath,
  });

  final List<String> pathSegments;
  final String? remotePath;

  @override
  bool get isFolder => true;

  RemoteFolderEntry child(String id, String name, {String? remotePath}) =>
      RemoteFolderEntry(
        id: id,
        name: name,
        remotePath: remotePath,
        pathSegments: <String>[...pathSegments, name],
      );
}

class RemoteFileEntry extends RemoteEntry {
  const RemoteFileEntry({
    required super.id,
    required super.name,
    required this.sizeBytes,
    this.mimeType,
    this.parentPathSegments = const <String>[],
    this.remotePath,
  });

  final int sizeBytes;
  final String? mimeType;
  final List<String> parentPathSegments;
  final String? remotePath;

  @override
  bool get isFolder => false;

  String get sanitizedPath => (<String>[...parentPathSegments, name]).join('/');
}

class RemoteFilePayload {
  const RemoteFilePayload({
    required this.bytes,
    required this.sizeBytes,
    this.mimeType,
    this.fileName,
    this.etag,
  });

  final Uint8List bytes;
  final int sizeBytes;
  final String? mimeType;
  final String? fileName;
  final String? etag;
}

abstract class CloudDriveProvider {
  const CloudDriveProvider();

  IconData get icon;

  String get id;

  String get displayName;

  String get description;

  bool get isConnected;

  Future<void> ensureAuthenticated(BuildContext context);

  Future<List<RemoteEntry>> listChildren(RemoteFolderEntry? parent);

  Future<RemoteFilePayload> download(RemoteFileEntry file);

  bool supportsStreaming(RemoteFileEntry file) => false;

  String? streamingMimeType(RemoteFileEntry file) => file.mimeType;

  int? streamingLength(RemoteFileEntry file) =>
      file.sizeBytes > 0 ? file.sizeBytes : null;

  Stream<List<int>> openRead(RemoteFileEntry file) async* {
    yield (await download(file)).bytes;
  }
}
