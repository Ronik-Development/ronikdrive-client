import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../security/encryption_service.dart';
import '../shared/file_downloader.dart';
import '../shared/app_page_title.dart';
import '../shared/release_runtime_config.dart';
import 'public_transfer_failure.dart';
import 'share_link_security.dart';
import 'share_metadata_envelope.dart';
import 'share_link_crypto.dart';

typedef SharePasswordKeyDeriver =
    Future<SecretKey> Function({
      required String password,
      required List<int> salt,
    });

class PasswordSharePage extends StatefulWidget {
  const PasswordSharePage({
    super.key,
    required this.token,
    this.apiBaseUri,
    this.keyDeriver,
    this.linkFragment,
    this.fileSaver,
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  final String token;
  final Uri? apiBaseUri;
  final SharePasswordKeyDeriver? keyDeriver;

  /// Private fragment supplied by navigation, never included in an HTTP call.
  final String? linkFragment;
  final Future<void> Function(List<int> bytes, String fileName)? fileSaver;
  final http.Client? _httpClient;

  @override
  State<PasswordSharePage> createState() => _PasswordSharePageState();
}

class _PasswordSharePageState extends State<PasswordSharePage> {
  final TextEditingController _passwordController = TextEditingController();
  final http.Client _fallbackClient = http.Client();
  Map<String, dynamic>? _share;
  bool _loading = true;
  bool _downloading = false;
  bool _passwordVisible = false;
  String? _resolvedFileName;
  String? _error;
  SecretKey? _linkKey;
  bool get _linkMode => _share?['accessMode'] == 'link';

  http.Client get _httpClient => widget._httpClient ?? _fallbackClient;

  @override
  void initState() {
    super.initState();
    _loadShare();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    if (widget._httpClient == null) {
      _fallbackClient.close();
    }
    super.dispose();
  }

  Future<void> _loadShare() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _postJson(
        'shares/${Uri.encodeComponent(widget.token)}/metadata',
      );
      final expiresAt = _parseDate(data['expiresAt']);
      if (expiresAt != null && DateTime.now().toUtc().isAfter(expiresAt)) {
        throw const PublicTransferException(
          PublicTransferFailureKind.closedOrExpired,
        );
      }
      SecretKey? linkKey;
      String? resolvedName;
      if (data['accessMode'] == 'link') {
        if (data['kdf'] != 'none' ||
            data['iterations'] != 0 ||
            data['algorithm'] != 'aes-ctr-hmac-sha256' ||
            data.containsKey('saltBase64') ||
            data['metadataFormat'] != shareMetadataEnvelopeFormat ||
            data['downloadProofFormat'] != shareDownloadProofFormat) {
          throw const PublicTransferException(
            PublicTransferFailureKind.unsupportedMetadata,
          );
        }
        final fragment = widget.linkFragment ?? Uri.base.fragment;
        if (fragment.isEmpty) {
          throw const PublicTransferException(
            PublicTransferFailureKind.missingPrivateKey,
          );
        }
        try {
          linkKey = ShareLinkCrypto.parseFragment(fragment);
          resolvedName = (await _openProtectedMetadata(
            data,
            linkKey,
          ))!.fileName;
        } catch (_) {
          throw const PublicTransferException(
            PublicTransferFailureKind.invalidPrivateKey,
          );
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _share = data;
        _resolvedFileName = resolvedName;
        _linkKey = linkKey;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _share = null;
        _resolvedFileName = null;
        _linkKey = null;
        _error = publicTransferFailureMessage(
          error,
          action: PublicTransferAction.openShare,
        );
        _loading = false;
      });
    }
  }

  Future<void> _download() async {
    final share = _share;
    final password = _passwordController.text.trim();
    if (share == null || (!_linkMode && password.isEmpty) || _downloading) {
      return;
    }
    setState(() {
      _downloading = true;
      _error = null;
    });
    try {
      final saltBase64 = (share['saltBase64'] as String?)?.trim();
      if (!_linkMode && (saltBase64 == null || saltBase64.isEmpty)) {
        throw const PublicTransferException(
          PublicTransferFailureKind.unsupportedMetadata,
        );
      }
      final key = _linkMode
          ? _linkKey!
          : await (widget.keyDeriver ?? EncryptionService.instance.deriveKey)(
              password: password,
              salt: base64Decode(saltBase64!),
            );
      final protectedMetadata = await _openProtectedMetadata(share, key);
      if (!mounted) return;
      final fileName = protectedMetadata?.fileName ?? _legacyFileName(share);
      if (protectedMetadata != null && mounted) {
        setState(() => _resolvedFileName = protectedMetadata.fileName);
      }
      final encryptedBytes = await _downloadEncryptedPayload(
        share: share,
        key: key,
      );
      final plainBytes = await EncryptionService.instance.decryptData(
        encryptedBytes,
        key,
      );
      if (!mounted) return;
      await (widget.fileSaver ?? downloadFile)(plainBytes, fileName);
    } on SecretBoxAuthenticationError {
      _setError(
        _linkMode
            ? 'The complete link could not decrypt this file. Ask the sender for a new link.'
            : 'That password could not decrypt this file.',
      );
    } on FormatException {
      _setError(
        _linkMode
            ? 'The complete link could not decrypt this file. Ask the sender for a new link.'
            : 'That password could not decrypt this file.',
      );
    } catch (error) {
      _setError(
        publicTransferFailureMessage(
          error,
          action: PublicTransferAction.downloadShare,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
        });
      }
    }
  }

  Future<ProtectedShareMetadata?> _openProtectedMetadata(
    Map<String, dynamic> share,
    SecretKey key,
  ) async {
    final format = share['metadataFormat']?.toString().trim() ?? '';
    final envelope = share['encryptedMetadataBase64']?.toString().trim() ?? '';
    if (format.isEmpty && envelope.isEmpty) {
      return null;
    }
    if (format != shareMetadataEnvelopeFormat || envelope.isEmpty) {
      throw const PublicTransferException(
        PublicTransferFailureKind.unsupportedMetadata,
      );
    }
    return ShareMetadataEnvelope.open(encodedEnvelope: envelope, key: key);
  }

  Future<Uint8List> _downloadEncryptedPayload({
    required Map<String, dynamic> share,
    required SecretKey key,
  }) async {
    final proofFormat = share['downloadProofFormat']?.toString().trim() ?? '';
    String? accessProofBase64;
    if (proofFormat.isNotEmpty) {
      if (proofFormat != shareDownloadProofFormat) {
        throw const PublicTransferException(
          PublicTransferFailureKind.unsupportedProtection,
        );
      }
      accessProofBase64 = await deriveShareDownloadProof(
        shareKey: key,
        token: widget.token,
      );
    }
    final decoded = await _postJson(
      'shares/${Uri.encodeComponent(widget.token)}/download',
      timeout: const Duration(seconds: 90),
      fields: <String, Object?>{
        if (accessProofBase64 != null) 'accessProofBase64': accessProofBase64,
      },
    );
    final bytesBase64 = decoded['bytesBase64'];
    if (bytesBase64 is! String || bytesBase64.trim().isEmpty) {
      throw const PublicTransferException(
        PublicTransferFailureKind.responseIncomplete,
      );
    }
    return base64Decode(bytesBase64);
  }

  Future<Map<String, dynamic>> _postJson(
    String path, {
    Duration timeout = const Duration(seconds: 30),
    Map<String, Object?> fields = const <String, Object?>{},
  }) async {
    final apiBase =
        widget.apiBaseUri ?? ReleaseRuntimeConfig.resolveCheckoutApiBaseUri();
    final response = await _httpClient
        .post(
          apiBase.resolve(path),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, Object?>{'token': widget.token, ...fields}),
        )
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PublicTransferException(
        PublicTransferFailureKind.httpStatus,
        statusCode: response.statusCode,
      );
    }
    final decoded = _decodeJsonObject(response.body);
    if (decoded == null) {
      throw const PublicTransferException(
        PublicTransferFailureKind.responseIncomplete,
      );
    }
    return decoded;
  }

  Map<String, dynamic>? _decodeJsonObject(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  void _setError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _error = message;
    });
  }

  String _legacyFileName(Map<String, dynamic> share) {
    final raw = share['fileName'];
    if (raw is String && raw.trim().isNotEmpty) {
      return raw.trim();
    }
    return 'shared-file';
  }

  DateTime? _parseDate(Object? value) {
    if (value is String) {
      return DateTime.tryParse(value)?.toUtc();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final share = _share;
    return Scaffold(
      appBar: AppBar(title: const Text('RonikCloud share')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Icon(
                              Icons.lock_outline,
                              size: 42,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              share == null
                                  ? 'Shared file unavailable'
                                  : _resolvedFileName ??
                                        (share['metadataFormat'] ==
                                                shareMetadataEnvelopeFormat
                                            ? 'Password-protected file'
                                            : _legacyFileName(share)),
                              style: theme.textTheme.titleLarge,
                              textAlign: TextAlign.center,
                            ),
                            if (share != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _linkMode
                                    ? 'The complete link unlocks this file locally. Choose Download when you are ready. Anyone with the complete link can open this shared copy until access expires or is revoked.'
                                    : 'Enter the password from the sender. The '
                                          'filename is checked and decrypted locally '
                                          'before RonikCloud requests the encrypted file. '
                                          'New links also require a password-derived proof '
                                          'before encrypted bytes leave storage.',
                                style: theme.textTheme.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 18),
                              if (!_linkMode)
                                TextField(
                                  controller: _passwordController,
                                  decoration:
                                      const InputDecoration(
                                        labelText: 'Share password',
                                        border: OutlineInputBorder(),
                                      ).copyWith(
                                        suffixIcon: IconButton(
                                          tooltip: _passwordVisible
                                              ? 'Hide password'
                                              : 'Show password',
                                          onPressed: () => setState(
                                            () => _passwordVisible =
                                                !_passwordVisible,
                                          ),
                                          icon: Icon(
                                            _passwordVisible
                                                ? Icons.visibility_off_outlined
                                                : Icons.visibility_outlined,
                                          ),
                                        ),
                                      ),
                                  obscureText: !_passwordVisible,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  autofillHints: const <String>[
                                    AutofillHints.password,
                                  ],
                                  onSubmitted: (_) => _download(),
                                ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: _downloading ? null : _download,
                                icon: _downloading
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.download_rounded),
                                label: Text(
                                  _downloading
                                      ? 'Decrypting...'
                                      : 'Decrypt and download',
                                ),
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              Text(
                                _error!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.error,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              if (share == null) ...[
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  onPressed: _loading ? null : _loadShare,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Retry shared file'),
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
    ).withAppPageTitle('Open Protected Share | RonikCloud');
  }
}
