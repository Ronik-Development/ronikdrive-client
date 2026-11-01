import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'cloud_drive_provider.dart';
import 'remote_file_stream.dart';

class ICloudDriveMigrationProvider extends CloudDriveProvider {
  ICloudDriveMigrationProvider({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  String? _username;
  String? _appPassword;
  Uri? _baseUri;

  @override
  IconData get icon => Icons.cloud_outlined;

  @override
  String get id => 'icloud-drive';

  @override
  String get displayName => 'Apple iCloud Drive';

  @override
  String get description =>
      'Authenticate with your Apple ID app password and pick folders to import without downloading locally.';

  @override
  bool get isConnected =>
      _username != null && _appPassword != null && _baseUri != null;

  @override
  Future<void> ensureAuthenticated(BuildContext context) async {
    if (isConnected) {
      return;
    }

    final credentials = await showDialog<_ICloudCredentials>(
      context: context,
      builder: (context) => const _ICloudCredentialsDialog(),
    );

    if (credentials == null) {
      throw StateError('iCloud Drive sign-in was cancelled.');
    }

    _username = credentials.appleId.trim();
    _appPassword = credentials.appPassword.trim();

    if (_username!.isEmpty || _appPassword!.isEmpty) {
      throw StateError('Both Apple ID and app-specific password are required.');
    }

    _baseUri = await _resolveHomeUri();
  }

  @override
  Future<List<RemoteEntry>> listChildren(RemoteFolderEntry? parent) async {
    if (!isConnected) {
      throw StateError('iCloud Drive is not connected.');
    }

    final base = _baseUri!;
    final targetUri = parent?.remotePath != null
        ? base.resolve(parent!.remotePath!)
        : base;

    final response = await _propfind(targetUri, depth: 1);
    final document = XmlDocument.parse(response.body);
    final currentHref = _normalizeHref(targetUri, base);

    final entries = <RemoteEntry>[];

    for (final node in document.findAllElements(
      'response',
      namespace: 'DAV:',
    )) {
      final hrefNode = node.getElement('href', namespace: 'DAV:');
      if (hrefNode == null) {
        continue;
      }
      final href = hrefNode.innerText;
      final normalized = _normalizeHref(base.resolveUri(Uri.parse(href)), base);
      if (normalized == currentHref) {
        continue;
      }

      final propstat = node.getElement('propstat', namespace: 'DAV:');
      final prop = propstat?.getElement('prop', namespace: 'DAV:');
      if (prop == null) {
        continue;
      }

      final displayName =
          prop.getElement('displayname', namespace: 'DAV:')?.innerText ??
          _segmentName(normalized);
      final resourceType = prop.getElement('resourcetype', namespace: 'DAV:');
      final isCollection =
          resourceType?.getElement('collection', namespace: 'DAV:') != null;
      final contentLengthText = prop
          .getElement('getcontentlength', namespace: 'DAV:')
          ?.innerText;
      final sizeBytes = int.tryParse(contentLengthText ?? '0') ?? 0;

      if (isCollection) {
        entries.add(
          RemoteFolderEntry(
            id: normalized,
            name: displayName,
            remotePath: normalized,
            pathSegments: parent == null
                ? <String>[displayName]
                : <String>[...parent.pathSegments, displayName],
          ),
        );
      } else {
        entries.add(
          RemoteFileEntry(
            id: normalized,
            name: displayName,
            remotePath: normalized,
            sizeBytes: sizeBytes,
            mimeType: _guessMimeType(displayName),
            parentPathSegments: parent?.pathSegments ?? const <String>[],
          ),
        );
      }
    }

    entries.sort((a, b) {
      if (a.isFolder != b.isFolder) {
        return a.isFolder ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return entries;
  }

  @override
  Future<RemoteFilePayload> download(RemoteFileEntry file) async {
    if (!isConnected) {
      throw StateError('iCloud Drive is not connected.');
    }

    final base = _baseUri!;
    final remotePath = file.remotePath;
    if (remotePath == null) {
      throw StateError('The selected file does not have a valid remote path.');
    }

    final uri = base.resolve(remotePath);
    final response = await _httpClient.get(uri, headers: _authHeaders());
    if (response.statusCode != 200) {
      throw StateError(
        'Failed to download ${file.name} from iCloud (status ${response.statusCode}).',
      );
    }

    final bytes = response.bodyBytes;
    return RemoteFilePayload(
      bytes: Uint8List.fromList(bytes),
      sizeBytes: bytes.length,
      mimeType: file.mimeType,
      fileName: file.name,
      etag: response.headers['etag'],
    );
  }

  @override
  bool supportsStreaming(RemoteFileEntry file) => true;

  @override
  Stream<List<int>> openRead(RemoteFileEntry file) {
    if (!isConnected || file.remotePath == null) {
      throw StateError('iCloud file is unavailable.');
    }
    return readRemoteFileStream(
      client: _httpClient,
      method: 'GET',
      uri: _baseUri!.resolve(file.remotePath!),
      headers: _authHeaders(),
      expectedLength: file.sizeBytes > 0 ? file.sizeBytes : null,
    );
  }

  Future<Uri> _resolveHomeUri() async {
    final initial = Uri.parse('https://caldav.icloud.com/');
    final response = await _propfind(initial, depth: 0);
    if (response.statusCode == 401) {
      throw StateError('Your Apple ID credentials were rejected.');
    }
    if (response.statusCode != 207) {
      throw StateError(
        'Unexpected response ${response.statusCode} when resolving iCloud Drive root.',
      );
    }

    final document = XmlDocument.parse(response.body);
    final principalHref = document
        .findAllElements('current-user-principal', namespace: 'DAV:')
        .expand((node) => node.findAllElements('href', namespace: 'DAV:'))
        .map((node) => node.innerText)
        .firstWhere(
          (href) => href.isNotEmpty,
          orElse: () =>
              throw StateError('iCloud Drive did not return a principal home.'),
        );

    final principalUri = response.request!.url.resolve(principalHref);
    final principalResponse = await _propfind(principalUri, depth: 0);
    if (principalResponse.statusCode != 207) {
      throw StateError('Unable to resolve iCloud Drive home directory.');
    }

    final principalDoc = XmlDocument.parse(principalResponse.body);
    final homeHref = principalDoc
        .findAllElements('home-set', namespace: 'urn:ietf:params:xml:ns:caldav')
        .expand((node) => node.findAllElements('href', namespace: 'DAV:'))
        .map((node) => node.innerText)
        .cast<String?>()
        .firstWhere(
          (href) => href != null && href.isNotEmpty,
          orElse: () => null,
        );

    final candidate =
        homeHref ??
        principalHref.replaceFirst(RegExp(r'principal/?$'), 'home/');
    final resolved = principalResponse.request!.url.resolve(candidate);
    return resolved;
  }

  Future<http.Response> _propfind(Uri uri, {required int depth}) async {
    final request = http.Request('PROPFIND', uri);
    request.headers.addAll(<String, String>{
      'Depth': '$depth',
      'Authorization': _authHeader(),
      'Content-Type': 'text/xml; charset=utf-8',
      'User-Agent': 'cloud-storage-migrator',
    });
    request.body = '''<?xml version="1.0" encoding="utf-8"?>
<a:propfind xmlns:a="DAV:" xmlns:oc="http://apple.com/ns/icloud/">
  <a:prop>
    <a:displayname/>
    <a:resourcetype/>
    <a:getcontentlength/>
    <oc:etag/>
    <a:current-user-principal/>
  </a:prop>
</a:propfind>''';

    final streamed = await _httpClient.send(request);
    return http.Response.fromStream(streamed);
  }

  Map<String, String> _authHeaders({Map<String, String>? extra}) {
    final headers = <String, String>{
      'Authorization': _authHeader(),
      'User-Agent': 'cloud-storage-migrator',
    };
    if (extra != null) {
      headers.addAll(extra);
    }
    return headers;
  }

  String _authHeader() {
    final username = _username;
    final password = _appPassword;
    if (username == null || password == null) {
      throw StateError('Missing iCloud credentials.');
    }
    final credentials = base64Encode(utf8.encode('$username:$password'));
    return 'Basic $credentials';
  }

  String _normalizeHref(Uri uri, Uri base) {
    final normalized = uri.replace(query: '', fragment: '');
    final relativePath = normalized.path.startsWith(base.path)
        ? normalized.path.substring(base.path.length)
        : normalized.path;
    final trimmed = relativePath.startsWith('/')
        ? relativePath.substring(1)
        : relativePath;
    return trimmed;
  }

  String _segmentName(String href) {
    final sanitized = href.endsWith('/')
        ? href.substring(0, href.length - 1)
        : href;
    final segments = sanitized.split('/');
    if (segments.isEmpty) {
      return href;
    }
    return Uri.decodeComponent(segments.last);
  }

  String? _guessMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.heic')) {
      return 'image/heic';
    }
    if (lower.endsWith('.pdf')) {
      return 'application/pdf';
    }
    if (lower.endsWith('.txt')) {
      return 'text/plain';
    }
    if (lower.endsWith('.mov')) {
      return 'video/quicktime';
    }
    if (lower.endsWith('.mp4')) {
      return 'video/mp4';
    }
    return null;
  }
}

class _ICloudCredentials {
  const _ICloudCredentials({required this.appleId, required this.appPassword});

  final String appleId;
  final String appPassword;
}

class _ICloudCredentialsDialog extends StatefulWidget {
  const _ICloudCredentialsDialog();

  @override
  State<_ICloudCredentialsDialog> createState() =>
      _ICloudCredentialsDialogState();
}

class _ICloudCredentialsDialogState extends State<_ICloudCredentialsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _appleIdController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _appleIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connect iCloud Drive'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your Apple ID email and an app-specific password. Your credentials are used only to communicate with Apple directly.',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _appleIdController,
              decoration: const InputDecoration(labelText: 'Apple ID email'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Apple ID is required';
                }
                if (!value.contains('@')) {
                  return 'Enter a valid Apple ID email';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'App-specific password',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'App-specific password is required';
                }
                if (value.trim().length < 8) {
                  return 'App-specific passwords are typically 16 characters.';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Need one? Generate an app-specific password from appleid.apple.com and paste it here.',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() ?? false) {
              Navigator.of(context).pop(
                _ICloudCredentials(
                  appleId: _appleIdController.text,
                  appPassword: _passwordController.text,
                ),
              );
            }
          },
          child: const Text('Connect'),
        ),
      ],
    );
  }
}
