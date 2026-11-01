import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'cloud_drive_provider.dart';
import 'remote_file_stream.dart';
import 'oauth_web_view_page.dart';
import 'oauth_pkce.dart';

class OneDriveMigrationProvider extends CloudDriveProvider {
  OneDriveMigrationProvider({
    http.Client? httpClient,
    String? clientId,
    String? redirectUri,
    List<String>? scopes,
    AssetBundle? assetBundle,
  }) : _httpClient = httpClient ?? http.Client(),
       _clientId =
           clientId ?? const String.fromEnvironment('ONEDRIVE_CLIENT_ID'),
       _redirectUri = Uri.parse(
         redirectUri ??
             const String.fromEnvironment(
               'ONEDRIVE_REDIRECT_URI',
               defaultValue: 'https://localhost/oauth2redirect',
             ),
       ),
       _scopes = scopes ?? const <String>['Files.Read', 'User.Read'],
       _assetBundle = assetBundle ?? rootBundle;

  final http.Client _httpClient;
  final AssetBundle _assetBundle;
  String _clientId;
  Uri _redirectUri;
  List<String> _scopes;

  String? _accessToken;
  DateTime? _tokenExpiry;
  bool _configurationLoaded = false;

  @override
  IconData get icon => Icons.cloud_sync_outlined;

  @override
  String get id => 'onedrive';

  @override
  String get displayName => 'Microsoft OneDrive';

  @override
  String get description =>
      'Connect Microsoft OneDrive and copy selected folders into RonikCloud.';

  @override
  bool get isConnected =>
      _accessToken != null &&
      _tokenExpiry != null &&
      _tokenExpiry!.isAfter(DateTime.now().add(const Duration(minutes: 1)));

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
        'OneDrive migration is not configured. Add assets/config/onedrive_oauth.json '
        'or provide ONEDRIVE_CLIENT_ID/ONEDRIVE_REDIRECT_URI via --dart-define.',
      );
    }

    final state = _generateState();
    final pkce = OAuthPkcePair.generate();
    final authorizationUri = Uri.https(
      'login.microsoftonline.com',
      '/common/oauth2/v2.0/authorize',
      <String, String>{
        'client_id': _clientId,
        'redirect_uri': _redirectUri.toString(),
        'response_type': 'code',
        'response_mode': 'query',
        'code_challenge': pkce.challenge,
        'code_challenge_method': 'S256',
        'scope': _scopes.join(' '),
        'prompt': 'select_account',
        'state': state,
      },
    );

    final redirect = await Navigator.of(context).push<Uri>(
      MaterialPageRoute<Uri>(
        builder: (context) => OAuthWebViewPage(
          authorizationUri: authorizationUri,
          redirectUri: _redirectUri,
          title: 'Connect OneDrive',
        ),
      ),
    );

    if (redirect == null) {
      throw StateError('The OneDrive sign-in flow was cancelled.');
    }

    final token = await exchangeOAuthAuthorizationCode(
      client: _httpClient,
      tokenEndpoint: Uri.parse(
        'https://login.microsoftonline.com/common/oauth2/v2.0/token',
      ),
      redirect: redirect,
      expectedState: state,
      clientId: _clientId,
      codeVerifier: pkce.verifier,
      redirectUri: _redirectUri,
      extraFields: <String, String>{'scope': _scopes.join(' ')},
    );
    final accessToken = token['access_token'] as String?;
    final expiresInRaw = token['expires_in']?.toString();

    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('OneDrive did not return an access token.');
    }

    final expiresIn = int.tryParse(expiresInRaw ?? '0') ?? 0;
    _accessToken = accessToken;
    _tokenExpiry = DateTime.now().add(
      Duration(seconds: expiresIn > 0 ? expiresIn : 3600),
    );
  }

  @override
  Future<List<RemoteEntry>> listChildren(RemoteFolderEntry? parent) async {
    if (!isConnected) {
      throw StateError('OneDrive is not connected.');
    }

    final path = parent == null
        ? '/v1.0/me/drive/root/children'
        : '/v1.0/me/drive/items/${Uri.encodeComponent(parent.id)}/children';
    final uri = Uri.https('graph.microsoft.com', path, <String, String>{
      r'$select': 'id,name,size,file,folder',
      r'$top': '200',
    });

    final entries = <RemoteEntry>[];
    Uri? nextUri = uri;
    while (nextUri != null) {
      final response = await _httpClient.get(nextUri, headers: _authHeaders());
      if (response.statusCode != 200) {
        throw StateError(
          'OneDrive list request failed with status ${response.statusCode}.',
        );
      }

      final decoded = json.decode(response.body) as Map<String, dynamic>;
      final values = decoded['value'];
      if (values is List) {
        for (final raw in values) {
          if (raw is! Map<String, dynamic>) {
            continue;
          }
          final id = raw['id'] as String?;
          final name = raw['name'] as String? ?? 'Untitled';
          if (id == null || id.isEmpty) {
            continue;
          }
          if (raw['folder'] is Map) {
            entries.add(
              RemoteFolderEntry(
                id: id,
                name: name,
                pathSegments: parent == null
                    ? <String>[name]
                    : <String>[...parent.pathSegments, name],
              ),
            );
          } else {
            final fileInfo = raw['file'];
            entries.add(
              RemoteFileEntry(
                id: id,
                name: name,
                sizeBytes: (raw['size'] as num?)?.round() ?? 0,
                mimeType: fileInfo is Map
                    ? fileInfo['mimeType'] as String?
                    : null,
                parentPathSegments: parent?.pathSegments ?? const <String>[],
              ),
            );
          }
        }
      }

      final nextLink = decoded['@odata.nextLink'] as String?;
      nextUri = nextLink == null || nextLink.isEmpty
          ? null
          : Uri.parse(nextLink);
    }

    entries.sort(_compareRemoteEntries);
    return entries;
  }

  @override
  Future<RemoteFilePayload> download(RemoteFileEntry file) async {
    if (!isConnected) {
      throw StateError('OneDrive is not connected.');
    }

    final uri = Uri.https(
      'graph.microsoft.com',
      '/v1.0/me/drive/items/${Uri.encodeComponent(file.id)}/content',
    );
    final response = await _httpClient.get(uri, headers: _authHeaders());
    if (response.statusCode != 200) {
      throw StateError(
        'Failed to download ${file.name} from OneDrive (status ${response.statusCode}).',
      );
    }

    return RemoteFilePayload(
      bytes: Uint8List.fromList(response.bodyBytes),
      sizeBytes: response.bodyBytes.length,
      mimeType: file.mimeType,
      fileName: file.name,
      etag: response.headers['etag'],
    );
  }

  @override
  bool supportsStreaming(RemoteFileEntry file) => true;

  @override
  Stream<List<int>> openRead(RemoteFileEntry file) {
    if (!isConnected) throw StateError('OneDrive is not connected.');
    return readRemoteFileStream(
      client: _httpClient,
      method: 'GET',
      uri: Uri.https(
        'graph.microsoft.com',
        '/v1.0/me/drive/items/${Uri.encodeComponent(file.id)}/content',
      ),
      headers: _authHeaders(),
      expectedLength: file.sizeBytes > 0 ? file.sizeBytes : null,
    );
  }

  Map<String, String> _authHeaders() => <String, String>{
    'Authorization': 'Bearer $_accessToken',
    'Accept': 'application/json',
  };

  Future<void> _loadConfigurationIfNeeded() async {
    if (_configurationLoaded || _clientId.isNotEmpty) {
      _configurationLoaded = true;
      return;
    }

    try {
      final raw = await _assetBundle.loadString(
        'assets/config/onedrive_oauth.json',
      );
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) {
        final assetClientId = decoded['clientId'] as String?;
        final assetRedirectUri = decoded['redirectUri'] as String?;
        final assetScopes = decoded['scopes'];
        if (_clientId.isEmpty &&
            assetClientId != null &&
            assetClientId.isNotEmpty) {
          _clientId = assetClientId.trim();
        }
        if (assetRedirectUri != null && assetRedirectUri.isNotEmpty) {
          _redirectUri = Uri.parse(assetRedirectUri.trim());
        }
        if (assetScopes is List) {
          final parsedScopes = assetScopes
              .whereType<String>()
              .map((scope) => scope.trim())
              .where((scope) => scope.isNotEmpty)
              .toList();
          if (parsedScopes.isNotEmpty) {
            _scopes = parsedScopes;
          }
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
}

int _compareRemoteEntries(RemoteEntry a, RemoteEntry b) {
  if (a.isFolder != b.isFolder) {
    return a.isFolder ? -1 : 1;
  }
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}
