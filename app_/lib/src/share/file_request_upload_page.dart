import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../security/encryption_service.dart';
import '../shared/app_page_title.dart';
import '../shared/release_runtime_config.dart';
import 'file_request_metadata_envelope.dart';
import 'public_transfer_failure.dart';
import 'file_request_resumable_upload.dart';
import '../storage/upload_coordinator.dart';
import '../storage/transfer_journal.dart';
import '../shared/web_folder_upload_picker_stub.dart'
    if (dart.library.js_interop) '../shared/web_folder_upload_picker_html.dart'
    as web_picker;

class FileRequestUploadPage extends StatefulWidget {
  const FileRequestUploadPage({
    super.key,
    required this.token,
    this.apiBaseUri,
    this.requestKeyBase64,
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  final String token;
  final Uri? apiBaseUri;
  final String? requestKeyBase64;
  final http.Client? _httpClient;

  @override
  State<FileRequestUploadPage> createState() => _FileRequestUploadPageState();
}

class _FileRequestUploadPageState extends State<FileRequestUploadPage> {
  final http.Client _fallbackClient = http.Client();
  Map<String, dynamic>? _request;
  bool _loading = true;
  bool _uploading = false;
  String? _error;
  String? _success;
  String? _requestTitle;
  final _uploads = UploadCoordinator(
    scheduler: UploadCoordinator.instance.scheduler,
  );

  http.Client get _httpClient => widget._httpClient ?? _fallbackClient;

  @override
  void initState() {
    super.initState();
    _loadRequest();
  }

  @override
  void dispose() {
    _uploads.cancelAll();
    if (widget._httpClient == null) {
      _fallbackClient.close();
    }
    super.dispose();
  }

  Future<void> _loadRequest() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final key = _requestKey();
      final data = await _postJson(
        'file-requests/${Uri.encodeComponent(widget.token)}/metadata',
        const <String, Object?>{},
      );
      final expiresAt = _parseDate(data['expiresAt']);
      if (data['revoked'] == true ||
          (expiresAt != null && !expiresAt.isAfter(DateTime.now().toUtc()))) {
        throw const PublicTransferException(
          PublicTransferFailureKind.closedOrExpired,
        );
      }
      final uploadCount = _intValue(data['uploadCount']);
      final maxUploads = _intValue(data['maxUploads']);
      if (maxUploads > 0 && uploadCount >= maxUploads) {
        throw const PublicTransferException(
          PublicTransferFailureKind.uploadLimitReached,
        );
      }
      final metadataFormat = data['metadataFormat']?.toString().trim() ?? '';
      final String requestTitle;
      if (metadataFormat == fileRequestTitleMetadataFormat) {
        requestTitle = await FileRequestMetadataEnvelope.openTitle(
          encodedEnvelope:
              data['encryptedTitleBase64']?.toString().trim() ?? '',
          key: key,
        );
      } else if (metadataFormat.isEmpty ||
          metadataFormat == legacyFileRequestMetadataFormat) {
        final legacyTitle = data['title']?.toString().trim() ?? '';
        requestTitle = legacyTitle.isEmpty
            ? legacyFileRequestCompatibilityTitle
            : legacyTitle;
      } else {
        throw const PublicTransferException(
          PublicTransferFailureKind.unsupportedMetadata,
        );
      }
      if (!mounted) return;
      setState(() {
        _request = data;
        _requestTitle = requestTitle;
        _loading = false;
      });
    } on SecretBoxAuthenticationError {
      _setLoadError(
        const PublicTransferException(
          PublicTransferFailureKind.invalidPrivateKey,
        ),
      );
    } on FileRequestMetadataException {
      _setLoadError(
        const PublicTransferException(
          PublicTransferFailureKind.unsupportedMetadata,
        ),
      );
    } catch (error) {
      _setLoadError(error);
    }
  }

  void _setLoadError(Object error) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _request = null;
      _requestTitle = null;
      _error = publicTransferFailureMessage(
        error,
        action: PublicTransferAction.openFileRequest,
      );
    });
  }

  Future<void> _pickAndUpload() async {
    final request = _request;
    if (request == null || _uploading) return;
    setState(() {
      _uploading = true;
      _error = null;
      _success = null;
    });
    try {
      final key = _requestKey();
      if (UploadCoordinator.enabled) {
        await _pickResumable(request, key);
        return;
      }
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw const PublicTransferException(
          PublicTransferFailureKind.selectedFileUnreadable,
        );
      }
      final maximum = _intValue(request['maxFileBytes']);
      if (maximum > 0 && bytes.length > maximum) {
        throw PublicTransferException(
          PublicTransferFailureKind.selectedFileTooLarge,
          maximumBytes: maximum,
        );
      }

      final encryptedBytes = await EncryptionService.instance.encryptData(
        bytes,
        key,
      );
      final safeName = file.name.trim().isEmpty
          ? 'uploaded-file'
          : file.name.trim();
      final contentType = _contentTypeForName(safeName);
      final encryptedMetadataBase64 =
          await FileRequestMetadataEnvelope.sealUpload(
            fileName: safeName,
            contentType: contentType,
            key: key,
          );
      final authorization = await _postJson(
        'file-requests/${Uri.encodeComponent(widget.token)}/authorize',
        <String, Object?>{
          'plainSize': bytes.length,
          'encryptedSize': encryptedBytes.length,
        },
      );
      final uploadUrl = Uri.tryParse(authorization['url']?.toString() ?? '');
      final uploadId = authorization['uploadId']?.toString() ?? '';
      if (uploadUrl == null || uploadId.isEmpty) {
        throw const PublicTransferException(
          PublicTransferFailureKind.authorizationIncomplete,
        );
      }
      final putResponse = await _httpClient
          .put(
            uploadUrl,
            headers: const <String, String>{
              'Content-Type': 'application/octet-stream',
            },
            body: encryptedBytes,
          )
          .timeout(const Duration(minutes: 5));
      if (putResponse.statusCode < 200 || putResponse.statusCode >= 300) {
        throw PublicTransferException(
          PublicTransferFailureKind.uploadRejected,
          statusCode: putResponse.statusCode,
        );
      }
      await _postJson(
        'file-requests/${Uri.encodeComponent(widget.token)}/complete',
        FileRequestMetadataEnvelope.protectedCompletionPayload(
          uploadId: uploadId,
          encryptedMetadataBase64: encryptedMetadataBase64,
        ),
        expectedStatus: 201,
      );
      if (!mounted) return;
      setState(() {
        _success = '$safeName was encrypted in this browser and uploaded.';
      });
      await _loadRequest();
    } on SecretBoxAuthenticationError {
      _setError('The private request key is invalid. Ask for a new link.');
    } catch (error) {
      _setError(
        publicTransferFailureMessage(
          error,
          action: PublicTransferAction.uploadFile,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickResumable(
    Map<String, dynamic> request,
    SecretKey key,
  ) async {
    late final String name;
    late final int length;
    late final Stream<List<int>> Function() openRead;
    if (kIsWeb) {
      final selected = await web_picker.pickWebUploadFiles(
        allowMultiple: false,
      );
      if (selected.isEmpty) return;
      final file = selected.single;
      name = file.name;
      length = file.sizeBytes;
      openRead = () => file.openRead();
    } else {
      final selected = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: false,
        withReadStream: false,
      );
      if (selected == null || selected.files.isEmpty) return;
      final file = selected.files.single;
      name = file.name;
      length = file.size;
      openRead = () => file.xFile.openRead();
    }
    if (!mounted) return;
    final maximum = _intValue(request['maxFileBytes']);
    if (maximum > 0 && length > maximum) {
      throw PublicTransferException(
        PublicTransferFailureKind.selectedFileTooLarge,
        maximumBytes: maximum,
      );
    }
    final base =
        widget.apiBaseUri ?? ReleaseRuntimeConfig.resolveCheckoutApiBaseUri();
    final journal = await TransferJournal.open(
      preferences: await SharedPreferences.getInstance(),
      uid: crypto.sha256.convert(utf8.encode(widget.token)).toString(),
      scope: 'public-request:${base.toString()}',
    );
    try {
      final safeName = name.trim().isEmpty ? 'uploaded-file' : name.trim();
      await uploadResumableFileRequest(
        api: FileRequestSessionApi(
          client: _httpClient,
          baseUri: base,
          requestToken: widget.token,
        ),
        coordinator: _uploads,
        journal: journal,
        key: key,
        name: safeName,
        contentType: _contentTypeForName(safeName),
        length: length,
        openRead: openRead,
        isActive: () => mounted,
      );
      if (!mounted) return;
      setState(
        () => _success = '$safeName was encrypted on this device and uploaded.',
      );
      await _loadRequest();
    } finally {
      journal.dispose();
    }
  }

  SecretKey _requestKey() {
    var raw = widget.requestKeyBase64?.trim() ?? '';
    if (raw.isEmpty) {
      final fragment = Uri.base.fragment;
      final parameters = Uri.splitQueryString(fragment);
      raw = parameters['key']?.trim() ?? '';
    }
    if (raw.isEmpty) {
      throw const PublicTransferException(
        PublicTransferFailureKind.missingPrivateKey,
      );
    }
    try {
      final bytes = base64Url.decode(base64Url.normalize(raw));
      if (bytes.length != 32) throw const FormatException();
      return SecretKey(bytes);
    } on FormatException {
      throw const PublicTransferException(
        PublicTransferFailureKind.invalidPrivateKey,
      );
    }
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, Object?> body, {
    int expectedStatus = 200,
  }) async {
    final apiBase =
        widget.apiBaseUri ?? ReleaseRuntimeConfig.resolveCheckoutApiBaseUri();
    final response = await _httpClient
        .post(
          apiBase.resolve(path),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 90));
    if (response.statusCode != expectedStatus) {
      throw PublicTransferException(
        PublicTransferFailureKind.httpStatus,
        statusCode: response.statusCode,
      );
    }
    final decoded = _decodeJson(response.body);
    return decoded;
  }

  Map<String, dynamic> _decodeJson(String body) {
    try {
      final value = jsonDecode(body);
      return value is Map<String, dynamic> ? value : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
  }

  static int _intValue(Object? value) {
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime? _parseDate(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '')?.toUtc();

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  static String _contentTypeForName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.txt')) return 'text/plain';
    return 'application/octet-stream';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final request = _request;
    final requestExpiry = request == null
        ? null
        : _parseDate(request['expiresAt'])?.toLocal();
    final maximumUploads = request == null
        ? 0
        : _intValue(request['maxUploads']);
    final completedUploads = request == null
        ? 0
        : _intValue(request['uploadCount']);
    final remainingUploads = maximumUploads > completedUploads
        ? maximumUploads - completedUploads
        : 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Send files securely')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Icon(
                              Icons.enhanced_encryption_outlined,
                              size: 48,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _requestTitle ?? 'File request unavailable',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall,
                            ),
                            if (request != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                'Your file is encrypted locally before upload. RonikCloud never receives the key from the private URL fragment.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 18),
                              FilledButton.icon(
                                onPressed: _uploading ? null : _pickAndUpload,
                                icon: _uploading
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.upload_file_outlined),
                                label: Text(
                                  _uploading
                                      ? 'Encrypting and uploading…'
                                      : 'Choose file',
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Maximum file size: ${_formatBytes(_intValue(request['maxFileBytes']))}',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$remainingUploads submission${remainingUploads == 1 ? '' : 's'} remaining',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall,
                              ),
                              if (requestExpiry != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Available until around '
                                  '${MaterialLocalizations.of(context).formatMediumDate(requestExpiry)} '
                                  '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(requestExpiry))}',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ],
                            if (_success != null) ...[
                              const SizedBox(height: 14),
                              Text(
                                _success!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                              if (request == null) ...[
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  onPressed: _loading ? null : _loadRequest,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Retry file request'),
                                ),
                              ],
                            ],
                            const SizedBox(height: 20),
                            const Divider(),
                            const SizedBox(height: 8),
                            Text(
                              'Protected by RonikCloud • Client-side encrypted',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    ).withAppPageTitle('Secure File Request | RonikCloud');
  }
}
