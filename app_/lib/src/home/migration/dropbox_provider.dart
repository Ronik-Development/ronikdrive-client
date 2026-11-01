import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'cloud_drive_provider.dart';
import 'remote_file_stream.dart';
import 'oauth_web_view_page.dart';
import 'oauth_pkce.dart';

class DropboxMigrationProvider extends CloudDriveProvider {
  DropboxMigrationProvider({
    http.Client? httpClient,
    String? clientId,
    String? redirectUri,
    AssetBundle? assetBundle,
  }) : _httpClient = httpClient ?? http.Client(),
       _clientId =
           clientId ?? const String.fromEnvironment('DROPBOX_CLIENT_ID'),
       _redirectUri = Uri.parse(
         redirectUri ??
             const String.fromEnvironment(
               'DROPBOX_REDIRECT_URI',
               defaultValue: 'https://localhost/oauth2redirect',
             ),
       ),
       _assetBundle = assetBundle ?? rootBundle;

  final http.Client _httpClient;
  final AssetBundle _assetBundle;
  String _clientId;
  Uri _redirectUri;

  String? _accessToken;
  DateTime? _tokenExpiry;
  bool _configurationLoaded = false;

  @override
  IconData get icon => Icons.inventory_2_outlined;

  @override
  String get id => 'dropbox';

  @override
  String get displayName => 'Dropbox';

  @override
  String get description =>
      'Browse Dropbox folders and import selected files into RonikCloud.';

  @override
  bool get isConnected =>
      _accessToken != null &&
      (_tokenExpiry == null ||
          _tokenExpiry!.isAfter(
            DateTime.now().add(const Duration(minutes: 1)),
          ));

  @override
  Future<void> ensureAuthenticated(BuildContext context) async {
    if (isConnected) {
      return;
    }

    await _loadConfigurationIfNeeded();
    if (!context.mounted) {
      return;
    }

    if (_clientId.isEmpty) {
      throw StateError(
        'Dropbox migration is not configured. Add assets/config/dropbox_oauth.json '
        'or provide DROPBOX_CLIENT_ID/DROPBOX_REDIRECT_URI via --dart-define.',
      );
    }

    final state = _generateState();
    final pkce = OAuthPkcePair.generate();
    final authorizationUri =
        Uri.https('www.dropbox.com', '/oauth2/authorize', <String, String>{
          'client_id': _clientId,
          'redirect_uri': _redirectUri.toString(),
          'response_type': 'code',
          'code_challenge': pkce.challenge,
          'code_challenge_method': 'S256',
          'token_access_type': 'online',
          'state': state,
        });

    final redirect = await Navigator.of(context).push<Uri>(
      MaterialPageRoute<Uri>(
        builder: (context) => OAuthWebViewPage(
          authorizationUri: authorizationUri,
          redirectUri: _redirectUri,
          title: 'Connect Dropbox',
        ),
      ),
    );

    if (redirect == null) {
      throw StateError('The Dropbox sign-in flow was cancelled.');
    }

    final token = await exchangeOAuthAuthorizationCode(
      client: _httpClient,
      tokenEndpoint: Uri.parse('https://api.dropboxapi.com/oauth2/token'),
      redirect: redirect,
      expectedState: state,
      clientId: _clientId,
      codeVerifier: pkce.verifier,
      redirectUri: _redirectUri,
    );
    final accessToken = token['access_token'] as String?;
    final expiresInRaw = token['expires_in']?.toString();

    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Dropbox did not return an access token.');
    }

    final expiresIn = int.tryParse(expiresInRaw ?? '0') ?? 0;
    _accessToken = accessToken;
    _tokenExpiry = expiresIn > 0
        ? DateTime.now().add(Duration(seconds: expiresIn))
        : null;
  }

  @override
  Future<List<RemoteEntry>> listChildren(RemoteFolderEntry? parent) async {
    if (!isConnected) {
      throw StateError('Dropbox is not connected.');
    }

    final entries = <RemoteEntry>[];
    String? cursor;
    var hasMore = false;
    var firstRequest = true;
    do {
      final response = firstRequest
          ? await _postJson(
              Uri.https('api.dropboxapi.com', '/2/files/list_folder'),
              <String, dynamic>{
                'path': parent?.remotePath ?? '',
                'recursive': false,
                'include_deleted': false,
              },
            )
          : await _postJson(
              Uri.https('api.dropboxapi.com', '/2/files/list_folder/continue'),
              <String, dynamic>{'cursor': cursor},
            );
      firstRequest = false;

      if (response.statusCode != 200) {
        throw StateError(
          'Dropbox list request failed with status ${response.statusCode}.',
        );
      }

      final decoded = json.decode(response.body) as Map<String, dynamic>;
      final rawEntries = decoded['entries'];
      if (rawEntries is List) {
        for (final raw in rawEntries) {
          if (raw is! Map<String, dynamic>) {
            continue;
          }
          final tag = raw['.tag'] as String?;
          final id = raw['id'] as String?;
          final name = raw['name'] as String? ?? 'Untitled';
          final path = raw['path_lower'] as String?;
          if (tag == 'folder') {
            final folderPath = path ?? '';
            entries.add(
              RemoteFolderEntry(
                id: folderPath.isEmpty ? name : folderPath,
                name: name,
                remotePath: folderPath,
                pathSegments: parent == null
                    ? <String>[name]
                    : <String>[...parent.pathSegments, name],
              ),
            );
          } else if (tag == 'file') {
            if (id == null && path == null) {
              continue;
            }
            entries.add(
              RemoteFileEntry(
                id: id ?? path!,
                name: name,
                remotePath: path,
                sizeBytes: (raw['size'] as num?)?.round() ?? 0,
                mimeType: _guessMimeType(name),
                parentPathSegments: parent?.pathSegments ?? const <String>[],
              ),
            );
          }
        }
      }

      cursor = decoded['cursor'] as String?;
      hasMore = decoded['has_more'] == true;
    } while (hasMore && (cursor ?? '').isNotEmpty);

    entries.sort(_compareRemoteEntries);
    return entries;
  }

  @override
  Future<RemoteFilePayload> download(RemoteFileEntry file) async {
    if (!isConnected) {
      throw StateError('Dropbox is not connected.');
    }

    final path = file.remotePath;
    if (path == null || path.isEmpty) {
      throw StateError('The selected Dropbox file does not have a path.');
    }

    final response = await _httpClient.post(
      Uri.https('content.dropboxapi.com', '/2/files/download'),
      headers: <String, String>{
        'Authorization': 'Bearer $_accessToken',
        'Dropbox-API-Arg': json.encode(<String, String>{'path': path}),
      },
    );
    if (response.statusCode != 200) {
      throw StateError(
        'Failed to download ${file.name} from Dropbox (status ${response.statusCode}).',
      );
    }

    return RemoteFilePayload(
      bytes: Uint8List.fromList(response.bodyBytes),
      sizeBytes: response.bodyBytes.length,
      mimeType: file.mimeType,
      fileName: file.name,
      etag: response.headers['dropbox-api-result'],
    );
  }

  @override
  bool supportsStreaming(RemoteFileEntry file) => true;

  @override
  Stream<List<int>> openRead(RemoteFileEntry file) {
    if (!isConnected || file.remotePath == null) {
      throw StateError('Dropbox file is unavailable.');
    }
    return readRemoteFileStream(
      client: _httpClient,
      method: 'POST',
      uri: Uri.https('content.dropboxapi.com', '/2/files/download'),
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Dropbox-API-Arg': json.encode({'path': file.remotePath}),
      },
      expectedLength: file.sizeBytes > 0 ? file.sizeBytes : null,
    );
  }

  Future<http.Response> _postJson(Uri uri, Map<String, dynamic> body) {
    return _httpClient.post(
      uri,
      headers: <String, String>{
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/json',
      },
      body: json.encode(body),
    );
  }

  Future<void> _loadConfigurationIfNeeded() async {
    if (_configurationLoaded || _clientId.isNotEmpty) {
      _configurationLoaded = true;
      return;
    }

    try {
      final raw = await _assetBundle.loadString(
        'assets/config/dropbox_oauth.json',
      );
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) {
        final assetClientId = decoded['clientId'] as String?;
        final assetRedirectUri = decoded['redirectUri'] as String?;
        if (_clientId.isEmpty &&
            assetClientId != null &&
            assetClientId.isNotEmpty) {
          _clientId = assetClientId.trim();
        }
        if (assetRedirectUri != null && assetRedirectUri.isNotEmpty) {
          _redirectUri = Uri.parse(assetRedirectUri.trim());
        }
      }
    } catch (_) {
      // Missing asset is fine. Dart defines are the other supported path.
    } finally {
      _configurationLoaded = true;
    }
  }

  String _generateState() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  String? _guessMimeType(String name) {
    final extension = name.split('.').last.toLowerCase();
    return switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'pdf' => 'application/pdf',
      'txt' => 'text/plain',
      'csv' => 'text/csv',
      'json' => 'application/json',
      'mp4' => 'video/mp4',
      'mp3' => 'audio/mpeg',
      _ => null,
    };
  }
}

int _compareRemoteEntries(RemoteEntry a, RemoteEntry b) {
  if (a.isFolder != b.isFolder) {
    return a.isFolder ? -1 : 1;
  }
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}
