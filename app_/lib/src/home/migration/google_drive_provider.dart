import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'cloud_drive_provider.dart';
import 'remote_file_stream.dart';
import 'oauth_web_view_page.dart';
import 'oauth_pkce.dart';

class GoogleDriveMigrationProvider extends CloudDriveProvider {
  GoogleDriveMigrationProvider({
    http.Client? httpClient,
    String? clientId,
    String? redirectUri,
    List<String>? scopes,
    AssetBundle? assetBundle,
  }) : _httpClient = httpClient ?? http.Client(),
       _clientId =
           clientId ?? const String.fromEnvironment('GOOGLE_DRIVE_CLIENT_ID'),
       _redirectUri = Uri.parse(
         redirectUri ??
             const String.fromEnvironment(
               'GOOGLE_DRIVE_REDIRECT_URI',
               defaultValue: 'https://localhost/oauth2redirect',
             ),
       ),
       _scopes =
           scopes ??
           const <String>['https://www.googleapis.com/auth/drive.readonly'],
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
  IconData get icon => Icons.drive_folder_upload_outlined;

  @override
  String get id => 'google-drive';

  @override
  String get displayName => 'Google Drive';

  @override
  String get description =>
      'Browse your Google Drive folders and import files directly.';

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
        'Google Drive migration is not configured. Update assets/config/google_drive_oauth.json or provide '
        'GOOGLE_DRIVE_CLIENT_ID/GOOGLE_DRIVE_REDIRECT_URI via --dart-define.',
      );
    }

    final state = _generateState();
    final pkce = OAuthPkcePair.generate();
    final authorizationUri =
        Uri.https('accounts.google.com', '/o/oauth2/v2/auth', <String, String>{
          'client_id': _clientId,
          'redirect_uri': _redirectUri.toString(),
          'response_type': 'code',
          'code_challenge': pkce.challenge,
          'code_challenge_method': 'S256',
          'scope': _scopes.join(' '),
          'include_granted_scopes': 'true',
          'prompt': 'consent',
          'state': state,
        });

    final redirect = await Navigator.of(context).push<Uri>(
      MaterialPageRoute<Uri>(
        builder: (context) => OAuthWebViewPage(
          authorizationUri: authorizationUri,
          redirectUri: _redirectUri,
          title: 'Connect Google Drive',
        ),
      ),
    );

    if (redirect == null) {
      throw StateError('The Google Drive sign-in flow was cancelled.');
    }

    final token = await exchangeOAuthAuthorizationCode(
      client: _httpClient,
      tokenEndpoint: Uri.parse('https://oauth2.googleapis.com/token'),
      redirect: redirect,
      expectedState: state,
      clientId: _clientId,
      codeVerifier: pkce.verifier,
      redirectUri: _redirectUri,
    );
    final accessToken = token['access_token'] as String?;
    final expiresInRaw = token['expires_in']?.toString();

    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Google Drive did not return an access token.');
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
      throw StateError('Google Drive is not connected.');
    }

    final folderId = parent?.id ?? 'root';
    final queryParameters = <String, String>{
      'q': "'${folderId.replaceAll("'", "\\'")}' in parents and trashed=false",
      'fields': 'files(id,name,mimeType,size)',
      'pageSize': '1000',
      'supportsAllDrives': 'true',
      'includeItemsFromAllDrives': 'true',
      'orderBy': 'folder,name',
    };

    final uri = Uri.https(
      'www.googleapis.com',
      '/drive/v3/files',
      queryParameters,
    );
    final response = await _httpClient.get(uri, headers: _authHeaders());

    if (response.statusCode != 200) {
      throw StateError(
        'Google Drive list request failed with status ${response.statusCode}.',
      );
    }

    final decoded = json.decode(response.body) as Map<String, dynamic>;
    final files = decoded['files'];
    if (files is! List) {
      return const <RemoteEntry>[];
    }

    final entries = <RemoteEntry>[];
    for (final dynamic raw in files) {
      if (raw is! Map<String, dynamic>) {
        continue;
      }
      final id = raw['id'] as String?;
      final name = raw['name'] as String? ?? 'Untitled';
      final mimeType = raw['mimeType'] as String?;
      if (id == null) {
        continue;
      }
      if (mimeType != null &&
          mimeType == 'application/vnd.google-apps.folder') {
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
        final sizeRaw = raw['size'];
        final size = sizeRaw is String
            ? int.tryParse(sizeRaw) ?? 0
            : (sizeRaw as int?) ?? 0;
        final exportTarget = _exportTargetForGoogleMime(mimeType);
        final displayName = exportTarget == null
            ? name
            : _withExtension(name, exportTarget.extension);
        entries.add(
          RemoteFileEntry(
            id: id,
            name: displayName,
            sizeBytes: size,
            mimeType: mimeType,
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
      throw StateError('Google Drive is not connected.');
    }

    final exportTarget = _exportTargetForGoogleMime(file.mimeType);
    final uri = exportTarget == null
        ? Uri.https(
            'www.googleapis.com',
            '/drive/v3/files/${file.id}',
            <String, String>{'alt': 'media'},
          )
        : Uri.https(
            'www.googleapis.com',
            '/drive/v3/files/${file.id}/export',
            <String, String>{'mimeType': exportTarget.mimeType},
          );
    final response = await _httpClient.get(uri, headers: _authHeaders());

    if (response.statusCode != 200) {
      throw StateError(
        'Failed to download ${file.name} (status ${response.statusCode}).',
      );
    }

    final bytes = response.bodyBytes;
    return RemoteFilePayload(
      bytes: Uint8List.fromList(bytes),
      sizeBytes: bytes.length,
      mimeType: exportTarget?.mimeType ?? file.mimeType,
      fileName: exportTarget == null
          ? file.name
          : _withExtension(file.name, exportTarget.extension),
      etag: response.headers['etag'],
    );
  }

  @override
  bool supportsStreaming(RemoteFileEntry file) => true;

  @override
  String? streamingMimeType(RemoteFileEntry file) =>
      _exportTargetForGoogleMime(file.mimeType)?.mimeType ?? file.mimeType;

  @override
  int? streamingLength(RemoteFileEntry file) =>
      _exportTargetForGoogleMime(file.mimeType) == null
      ? super.streamingLength(file)
      : null;

  @override
  Stream<List<int>> openRead(RemoteFileEntry file) {
    if (!isConnected || !supportsStreaming(file)) {
      throw StateError('The remote file is not available for streaming.');
    }
    final exportTarget = _exportTargetForGoogleMime(file.mimeType);
    return readRemoteFileStream(
      client: _httpClient,
      method: 'GET',
      uri: Uri.https(
        'www.googleapis.com',
        '/drive/v3/files/${file.id}${exportTarget == null ? '' : '/export'}',
        exportTarget == null
            ? {'alt': 'media'}
            : {'mimeType': exportTarget.mimeType},
      ),
      headers: _authHeaders(),
      expectedLength: exportTarget == null && file.sizeBytes > 0
          ? file.sizeBytes
          : null,
    );
  }

  Map<String, String> _authHeaders() => <String, String>{
    'Authorization': 'Bearer $_accessToken',
    'Accept': 'application/json',
  };

  String _generateState() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  Future<void> _loadConfigurationIfNeeded() async {
    if (_configurationLoaded || _clientId.isNotEmpty) {
      _configurationLoaded = true;
      return;
    }

    try {
      final raw = await _assetBundle.loadString(
        'assets/config/google_drive_oauth.json',
      );
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) {
        final assetClientId = decoded['clientId'] as String?;
        final assetRedirectUri = decoded['redirectUri'] as String?;
        final assetScopes = decoded['scopes'];

        if ((_clientId.isEmpty) &&
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
    } catch (error) {
      // Ignore missing asset or invalid JSON and fallback to environment variables.
    } finally {
      _configurationLoaded = true;
    }
  }
}

({String mimeType, String extension})? _exportTargetForGoogleMime(
  String? mimeType,
) {
  return switch (mimeType) {
    'application/vnd.google-apps.document' => (
      mimeType:
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      extension: '.docx',
    ),
    'application/vnd.google-apps.spreadsheet' => (
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      extension: '.xlsx',
    ),
    'application/vnd.google-apps.presentation' => (
      mimeType:
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      extension: '.pptx',
    ),
    'application/vnd.google-apps.drawing' => (
      mimeType: 'image/png',
      extension: '.png',
    ),
    'application/vnd.google-apps.script' => (
      mimeType: 'application/vnd.google-apps.script+json',
      extension: '.json',
    ),
    _ => null,
  };
}

String _withExtension(String name, String extension) {
  if (extension.isEmpty || name.toLowerCase().endsWith(extension)) {
    return name;
  }
  return '$name$extension';
}
