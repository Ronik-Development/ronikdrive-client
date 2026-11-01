import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:aws_s3_api/s3-2006-03-01.dart' as s3;
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../security/encryption_service.dart';
import '../shared/release_runtime_config.dart';
import '../shared/service_environment.dart';
import '../shared/user_facing_cloud_error.dart';
import 'cloud_storage_provider.dart';
import 'multipart_upload_checkpoint_sink.dart';
import 'upload_coordinator.dart';
import 'upload_part_transport.dart';
import 'upload_cipher.dart';
import 'wasabi_browser_upload_stub.dart'
    if (dart.library.js_interop) 'wasabi_browser_upload_web.dart';

part 'wasabi_storage_environment.dart';
part 'wasabi_storage_models.dart';

class WasabiStorageService implements CloudStorageProvider {
  static const String _defaultBucketRegion = 'us-east-1';
  static const String _defaultSigningRegion = 'us-east-1';
  static const int _multipartUploadThresholdBytes = 8 * 1024 * 1024;
  static const int _multipartUploadPartSizeBytes = 8 * 1024 * 1024;
  static const int _multipartUploadParallelism = 3;
  static const int _maxUploadAttempts = 3;
  // Wasabi only uses the global s3.wasabisys.com endpoint for us-east-1. All
  // other regions require the "s3.<region>.wasabisys.com" hostname even when
  // the signing region stays on us-east-1.
  static const String _globalEndpointRegion = 'us-east-1';
  static const String _defaultEndpoint = 'https://s3.wasabisys.com';

  WasabiStorageService._({
    required this.bucket,
    required String region,
    required this.signingRegion,
    required String endpointUrl,
    required String accessKey,
    required String secretKey,
    String? sessionToken,
    Future<String?> Function()? browserUploadIdTokenProvider,
    Uri? browserUploadProxyUri,
    Uri? browserDownloadProxyUri,
    Uri? authorizedObjectUri,
    List<String> serverManagedPrefixes = const <String>[],
    http.Client? httpClient,
    s3.S3? client,
  }) : _bucketRegion = region,
       _endpointUrl = endpointUrl,
       _client = client,
       _accessKey = accessKey,
       _secretKey = secretKey,
       _sessionToken = sessionToken,
       _browserUploadIdTokenProvider = browserUploadIdTokenProvider,
       _browserUploadProxyUri = browserUploadProxyUri,
       _browserDownloadProxyUri = browserDownloadProxyUri,
       _authorizedObjectUri = authorizedObjectUri,
       _serverManagedPrefixes = List<String>.unmodifiable(
         serverManagedPrefixes
             .map((value) => value.trim())
             .where((value) => value.isNotEmpty),
       ),
       _httpClient = httpClient ?? http.Client();

  factory WasabiStorageService({
    required String accessKey,
    required String secretKey,
    required String bucket,
    String region = _defaultBucketRegion,
    String endpointUrl = _defaultEndpoint,
    String signingRegion = _defaultSigningRegion,
    String? sessionToken,
    Future<String?> Function()? browserUploadIdTokenProvider,
    Uri? browserUploadProxyUri,
    Uri? browserDownloadProxyUri,
    Uri? authorizedObjectUri,
    List<String> serverManagedPrefixes = const <String>[],
    http.Client? httpClient,
  }) {
    final sanitizedEndpoint = _coerceEndpointForRegion(endpointUrl, region);
    try {
      Uri.parse(sanitizedEndpoint);
    } on FormatException {
      throw const WasabiConfigurationException(
        'The secure-storage endpoint configuration is invalid.',
      );
    }
    final normalizedSigningRegion = _coerceSigningRegion(signingRegion);
    final credentials = s3.AwsClientCredentials(
      accessKey: accessKey,
      secretKey: secretKey,
      sessionToken: sessionToken,
    );
    final client = s3.S3(
      region: normalizedSigningRegion,
      credentials: credentials,
      endpointUrl: sanitizedEndpoint,
    );
    return WasabiStorageService._(
      bucket: bucket,
      region: region,
      signingRegion: normalizedSigningRegion,
      endpointUrl: sanitizedEndpoint,
      accessKey: accessKey,
      secretKey: secretKey,
      sessionToken: sessionToken,
      client: client,
      browserUploadIdTokenProvider: browserUploadIdTokenProvider,
      browserUploadProxyUri: browserUploadProxyUri,
      browserDownloadProxyUri: browserDownloadProxyUri,
      authorizedObjectUri: authorizedObjectUri,
      serverManagedPrefixes: serverManagedPrefixes,
      httpClient: httpClient,
    );
  }

  factory WasabiStorageService.serverManaged({
    required String bucket,
    required Future<String?> Function() idTokenProvider,
    required Uri authorizedObjectUri,
    required List<String> serverManagedPrefixes,
    String region = _defaultBucketRegion,
    String endpointUrl = _defaultEndpoint,
    String signingRegion = _defaultSigningRegion,
    http.Client? httpClient,
  }) {
    final normalizedBucket = bucket.trim();
    final normalizedPrefixes = serverManagedPrefixes
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (normalizedBucket.isEmpty) {
      throw const WasabiConfigurationException('A storage bucket is required.');
    }
    if (normalizedPrefixes.isEmpty) {
      throw const WasabiConfigurationException(
        'At least one authorized storage scope is required.',
      );
    }
    return WasabiStorageService._(
      bucket: normalizedBucket,
      region: region,
      signingRegion: _coerceSigningRegion(signingRegion),
      endpointUrl: _coerceEndpointForRegion(endpointUrl, region),
      accessKey: '',
      secretKey: '',
      browserUploadIdTokenProvider: idTokenProvider,
      authorizedObjectUri: authorizedObjectUri,
      serverManagedPrefixes: normalizedPrefixes,
      httpClient: httpClient,
    );
  }

  factory WasabiStorageService.unconfigured({
    String region = _defaultBucketRegion,
    String signingRegion = _defaultSigningRegion,
    String endpointUrl = _defaultEndpoint,
  }) {
    return WasabiStorageService._(
      bucket: '',
      region: region,
      signingRegion: _coerceSigningRegion(signingRegion),
      endpointUrl: _coerceEndpointForRegion(endpointUrl, region),
      accessKey: '',
      secretKey: '',
    );
  }

  factory WasabiStorageService.fromEnvironment() {
    String firstNonEmpty(List<String> values) {
      for (final value in values) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
      }
      return '';
    }

    final accessKeyCandidates = <String>[
      _envWasabiClientAccessKey,
      _envWasabiClientAccessKeyId,
      _envWasabiAccessKey,
      _envWasabiAccessKeyId,
    ];
    final secretKeyCandidates = <String>[
      _envWasabiClientSecretKey,
      _envWasabiClientSecretAccessKey,
      _envWasabiSecretKey,
      _envWasabiSecretAccessKey,
    ];
    final bucketCandidates = <String>[_envWasabiClientBucket, _envWasabiBucket];
    final regionCandidates = <String>[_envWasabiClientRegion, _envWasabiRegion];
    final signingRegionCandidates = <String>[
      _envWasabiClientSigningRegion,
      _envWasabiSigningRegion,
    ];
    final endpointCandidates = <String>[
      _envWasabiClientEndpoint,
      _envWasabiClientEndpointUrl,
      _envWasabiEndpoint,
      _envWasabiEndpointUrl,
    ];

    final resolvedAccessKey = firstNonEmpty(accessKeyCandidates);
    final resolvedSecretKey = firstNonEmpty(secretKeyCandidates);
    final resolvedBucket = firstNonEmpty(bucketCandidates);
    final resolvedRegionCandidate = firstNonEmpty(regionCandidates);
    final resolvedSigningRegionCandidate = firstNonEmpty(
      signingRegionCandidates,
    );
    final resolvedEndpoint = firstNonEmpty(endpointCandidates);
    final endpointRegion = inferRegionFromEndpoint(resolvedEndpoint);
    final resolvedRegion = resolvedRegionCandidate.isNotEmpty
        ? resolvedRegionCandidate
        : (endpointRegion ?? _defaultBucketRegion);
    final resolvedSigningRegion = _coerceSigningRegion(
      resolvedSigningRegionCandidate.isNotEmpty
          ? resolvedSigningRegionCandidate
          : (resolvedRegion.isNotEmpty
                ? resolvedRegion
                : _defaultSigningRegion),
    );

    if (resolvedAccessKey.isEmpty ||
        resolvedSecretKey.isEmpty ||
        resolvedBucket.isEmpty) {
      return WasabiStorageService.unconfigured(
        region: resolvedRegion,
        signingRegion: resolvedSigningRegion,
        endpointUrl: resolvedEndpoint,
      );
    }

    final coercedEndpoint = _coerceEndpointForRegion(
      resolvedEndpoint,
      resolvedRegion,
    );

    if (!ServiceEnvironmentPolicy.allowsDirectStorageCredentials(
      environment: ServiceEnvironmentConfig.current,
      explicitlyAllowed: _envAllowDirectWasabiClientCredentials,
    )) {
      _logUpload(
        'Ignoring compile-time Wasabi client credentials. Direct credentials '
        'require an explicit production-only opt-in; local and staging clients '
        'must use fakes or provisioned environment-scoped credentials.',
      );
      return WasabiStorageService.unconfigured(
        region: resolvedRegion,
        signingRegion: resolvedSigningRegion,
        endpointUrl: coercedEndpoint,
      );
    }

    return WasabiStorageService(
      accessKey: resolvedAccessKey,
      secretKey: resolvedSecretKey,
      bucket: resolvedBucket,
      region: resolvedRegion,
      signingRegion: resolvedSigningRegion,
      endpointUrl: coercedEndpoint,
    );
  }

  final String bucket;
  String get region => _bucketRegion;
  String get accessKey => _accessKey;
  String get secretKey => _secretKey;
  final String signingRegion;
  String get endpointUrl => _endpointUrl;
  final String _accessKey;
  final String _secretKey;
  final String? _sessionToken;
  final Future<String?> Function()? _browserUploadIdTokenProvider;
  final Uri? _browserUploadProxyUri;
  final Uri? _browserDownloadProxyUri;
  final Uri? _authorizedObjectUri;
  final List<String> _serverManagedPrefixes;
  final http.Client _httpClient;
  s3.S3? _client;
  String _bucketRegion;
  String _endpointUrl;

  bool _isServerManagedObject(String objectKey) =>
      RegExp(r'^company_[a-f0-9]{28}/').hasMatch(objectKey) ||
      _serverManagedPrefixes.any(
        (prefix) => objectKey == prefix || objectKey.startsWith('$prefix/'),
      );

  bool get _hasDirectCredentials =>
      _client != null && _accessKey.isNotEmpty && _secretKey.isNotEmpty;

  bool get _hasServerManagedAccess =>
      _browserUploadIdTokenProvider != null &&
      _authorizedObjectUri != null &&
      _serverManagedPrefixes.isNotEmpty;

  @override
  bool get isConfigured =>
      bucket.isNotEmpty && (_hasDirectCredentials || _hasServerManagedAccess);

  static void _logUpload(String message) {
    if (!kDebugMode) {
      return;
    }
    final timestamp = DateTime.now().toIso8601String();
    debugPrint('[RonikCloud][wasabi-upload][$timestamp] $message');
  }

  @override
  Future<WasabiUploadResult> upload({
    required String objectKey,
    required Stream<List<int>> stream,
    required int length,
    String? contentType,
    SecretKey? encryptionKey,
    bool payloadAlreadyEncrypted = false,
    String? transferId,
    MultipartUploadCheckpointSink? checkpointSink,
    String? sourceFingerprint,
  }) async {
    if (encryptionKey != null && payloadAlreadyEncrypted) {
      throw const WasabiStorageException(
        'Upload protection is ambiguous. Provide an encryption key or mark '
        'the payload as already encrypted, but not both.',
      );
    }
    if (encryptionKey == null && !payloadAlreadyEncrypted) {
      throw const WasabiStorageException(
        'Upload blocked because client-side encryption was not provided.',
      );
    }
    const storageContentType = 'application/octet-stream';
    final resumableSink = checkpointSink is ResumableUploadCheckpointSink
        ? checkpointSink as ResumableUploadCheckpointSink
        : null;
    final saved = !UploadCoordinator.enabled || transferId == null
        ? null
        : resumableSink?.uploadCheckpoint(transferId);
    if (UploadCoordinator.enabled &&
        saved != null &&
        (sourceFingerprint == null ||
            saved['sourceFingerprint'] != sourceFingerprint)) {
      throw const UploadFailure('source_changed');
    }
    _logUpload('Preparing a client-encrypted upload.');

    if (!UploadCoordinator.enabled &&
        encryptionKey != null &&
        length <= _multipartUploadThresholdBytes) {
      _logUpload('Using the bounded buffered encryption path.');
      final plainBytes = await _streamToBytes(stream);
      final encryptedBytes = await _encryptBufferedPayload(
        bytes: plainBytes,
        encryptionKey: encryptionKey,
      );
      return _uploadBufferedBytes(
        objectKey: objectKey,
        bytes: encryptedBytes,
        contentType: storageContentType,
        allowRetry: true,
      );
    }

    Stream<List<int>> uploadStream = stream;
    int uploadLength = length;

    if (encryptionKey != null) {
      final algorithm = EncryptionService.instance.fileContentAlgorithm;
      final nonce = UploadCoordinator.enabled && saved?['nonce'] is String
          ? base64Decode(saved!['nonce'] as String)
          : algorithm.newNonce();
      if (UploadCoordinator.enabled &&
          transferId != null &&
          resumableSink != null) {
        await resumableSink.saveUploadCheckpoint(transferId, {
          ...?saved,
          'version': 1,
          'nonce': base64Encode(nonce),
          'sourceFingerprint': sourceFingerprint,
          'objectKey': objectKey,
        });
      }
      final macCompleter = Completer<Mac>();

      _logUpload('Starting streaming client-side encryption.');

      final encryptedStream = algorithm.encryptStream(
        stream,
        secretKey: encryptionKey,
        nonce: nonce,
        onMac: (mac) => macCompleter.complete(mac),
      );

      Stream<List<int>> protectedStream() async* {
        yield nonce;
        yield* encryptedStream;
        yield (await macCompleter.future).bytes;
      }

      uploadStream = UploadCoordinator.enabled
          ? encryptUploadStream(stream, encryptionKey, nonce)
          : protectedStream();
      uploadLength =
          length + algorithm.nonceLength + algorithm.macAlgorithm.macLength;
      _logUpload('Streaming encryption pipeline prepared.');
    }

    return _uploadStream(
      objectKey: objectKey,
      stream: uploadStream,
      length: uploadLength,
      contentType: storageContentType,
      allowRetry: true,
      transferId: transferId,
      checkpointSink: checkpointSink,
    );
  }

  Future<WasabiUploadResult> _uploadStream({
    required String objectKey,
    required Stream<List<int>> stream,
    required int length,
    String? contentType,
    bool allowRetry = true,
    String? transferId,
    MultipartUploadCheckpointSink? checkpointSink,
  }) async {
    _logUpload('Selecting an encrypted upload strategy.');
    if (_isServerManagedObject(objectKey) ||
        (UploadCoordinator.enabled && _browserUploadIdTokenProvider != null)) {
      return _uploadAuthorizedStream(
        objectKey: objectKey,
        stream: stream,
        length: length,
        contentType: contentType,
        transferId: transferId,
        checkpointSink: checkpointSink,
      );
    }
    if (length > _multipartUploadThresholdBytes) {
      _logUpload('Using the multipart encrypted upload path.');
      return _uploadMultipartStream(
        objectKey: objectKey,
        stream: stream,
        contentType: contentType,
        allowRetry: allowRetry,
        transferId: transferId,
        checkpointSink: checkpointSink,
      );
    }

    _logUpload('Using the buffered encrypted upload path.');
    return _uploadBufferedStream(
      objectKey: objectKey,
      stream: stream,
      contentType: contentType,
      allowRetry: allowRetry,
    );
  }

  Future<Map<String, dynamic>> _authorizeServerManagedObject({
    required String objectKey,
    required String action,
    String? contentType,
    int? contentLength,
  }) async {
    final tokenProvider = _browserUploadIdTokenProvider;
    if (tokenProvider == null) {
      throw const WasabiStorageException(
        'Secure storage access is not configured.',
      );
    }
    final token = await tokenProvider();
    if (token == null || token.trim().isEmpty) {
      throw const WasabiStorageException(
        'Sign in again to authorize this storage operation.',
      );
    }
    final uri =
        _authorizedObjectUri ??
        ReleaseRuntimeConfig.resolveCheckoutApiBaseUri().resolve(
          'storage/wasabi/authorize-object',
        );
    final response = await _httpClient
        .post(
          uri,
          headers: <String, String>{
            'Authorization': 'Bearer ${token.trim()}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'objectKey': objectKey,
            'action': action,
            if (contentType != null) 'contentType': contentType,
            if (contentLength != null) 'contentLength': contentLength,
          }),
        )
        .timeout(const Duration(seconds: 30));
    final decoded = _decodeJsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WasabiStorageException(
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.storageTransfer,
          code: _proxyErrorCode(decoded),
          httpStatus: response.statusCode,
        ),
      );
    }
    if (decoded == null || decoded['url'] is! String) {
      throw const WasabiStorageException(
        'Storage authorization returned an invalid response.',
      );
    }
    return decoded;
  }

  Future<WasabiUploadResult> _uploadAuthorizedStream({
    required String objectKey,
    required Stream<List<int>> stream,
    required int length,
    String? contentType,
    String? transferId,
    MultipartUploadCheckpointSink? checkpointSink,
  }) async {
    if (UploadCoordinator.enabled) {
      final api = uploadSessionApi;
      if (api == null) throw const WasabiStorageException('Sign in to upload.');
      await UploadCoordinator.instance.upload(
        objectKey: objectKey,
        length: length,
        ciphertext: stream,
        api: api,
        transferId: transferId,
        checkpointSink: checkpointSink is ResumableUploadCheckpointSink
            ? checkpointSink as ResumableUploadCheckpointSink
            : null,
        awaitMetadata: transferId != null,
        put: (_, _) async => throw const UploadFailure('unavailable'),
        putCancellable: (url, bytes, abortSignal, headers) => putUploadPart(
          headers: headers,
          client: _httpClient,
          url: url,
          bytes: bytes,
          abortSignal: abortSignal,
        ),
      );
      return WasabiUploadResult(objectKey: objectKey, bucket: bucket);
    }
    final resolvedContentType = contentType ?? 'application/octet-stream';
    final authorization = await _authorizeServerManagedObject(
      objectKey: objectKey,
      action: 'put',
      contentType: resolvedContentType,
      contentLength: length,
    );
    final request = http.StreamedRequest(
      'PUT',
      Uri.parse(authorization['url'] as String),
    );
    request.contentLength = length;
    request.headers['Content-Type'] = resolvedContentType;
    final responseFuture = _httpClient
        .send(request)
        .timeout(const Duration(minutes: 15));
    await request.sink.addStream(stream);
    await request.sink.close();
    final response = await responseFuture;
    await response.stream.drain<void>();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WasabiStorageException(
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.storageTransfer,
          httpStatus: response.statusCode,
        ),
      );
    }
    return WasabiUploadResult(
      objectKey: objectKey,
      bucket: bucket,
      eTag: response.headers['etag'],
    );
  }

  UploadSessionApi? get uploadSessionApi {
    final tokenProvider = _browserUploadIdTokenProvider;
    if (tokenProvider == null) return null;
    return UploadSessionApi(client: _httpClient, tokenProvider: tokenProvider);
  }

  Future<WasabiUploadResult> _uploadBufferedStream({
    required String objectKey,
    required Stream<List<int>> stream,
    String? contentType,
    required bool allowRetry,
  }) async {
    final fullBytes = await _streamToBytes(stream);

    return _uploadBufferedBytes(
      objectKey: objectKey,
      bytes: fullBytes,
      contentType: contentType,
      allowRetry: allowRetry,
    );
  }

  Future<WasabiUploadResult> _uploadBufferedBytes({
    required String objectKey,
    required Uint8List bytes,
    String? contentType,
    required bool allowRetry,
  }) async {
    _logUpload('Buffered encrypted payload is ready.');
    if (_isServerManagedObject(objectKey) ||
        (UploadCoordinator.enabled && _browserUploadIdTokenProvider != null)) {
      return _uploadAuthorizedStream(
        objectKey: objectKey,
        stream: Stream<List<int>>.value(bytes),
        length: bytes.length,
        contentType: contentType,
      );
    }

    Object? proxyFirstError;
    if (kIsWeb && _browserUploadIdTokenProvider != null) {
      try {
        _logUpload('Using the protected browser-upload path first.');
        final result = await _uploadBufferedBytesViaProxy(
          objectKey: objectKey,
          bytes: bytes,
          contentType: contentType,
        );
        _logUpload('The protected browser-upload path succeeded.');
        return result;
      } catch (error) {
        proxyFirstError = error;
        _logUpload(
          'The protected browser-upload path was unavailable; trying the '
          'compatible encrypted path.',
        );
      }
    }

    var attempt = 0;
    while (true) {
      attempt++;
      try {
        final client = _client;
        if (client == null) {
          throw const WasabiConfigurationException(
            'Secure storage is not configured. Refresh account storage access.',
          );
        }
        _logUpload('Starting an encrypted object upload attempt.');
        final String? eTag;
        if (kIsWeb) {
          final response = await putWasabiObjectViaBrowser(
            endpointUrl: endpointUrl,
            bucket: bucket,
            objectKey: objectKey,
            bytes: bytes,
            contentType: contentType ?? 'application/octet-stream',
            accessKey: accessKey,
            secretKey: secretKey,
            signingRegion: signingRegion,
            sessionToken: _sessionToken,
          );
          eTag = response.eTag;
        } else {
          final response = await client.putObject(
            bucket: bucket,
            key: objectKey,
            body: bytes,
            contentLength: bytes.length,
            contentType: contentType ?? 'application/octet-stream',
          );
          eTag = response.eTag;
        }
        _logUpload('Encrypted object upload succeeded.');

        return WasabiUploadResult(
          objectKey: objectKey,
          bucket: bucket,
          eTag: eTag,
        );
      } catch (error) {
        final isLastAttempt = attempt >= _maxUploadAttempts;
        _logUpload('An encrypted object upload attempt was unavailable.');

        if (kIsWeb &&
            _browserUploadIdTokenProvider != null &&
            proxyFirstError == null) {
          try {
            _logUpload('Trying the protected browser-upload fallback.');
            final result = await _uploadBufferedBytesViaProxy(
              objectKey: objectKey,
              bytes: bytes,
              contentType: contentType,
            );
            _logUpload('The protected browser-upload fallback succeeded.');
            return result;
          } catch (_) {
            _logUpload(
              'The protected browser-upload fallback was unavailable.',
            );
            if (isLastAttempt) {
              throw const WasabiStorageException(
                'Storage upload failed through both available paths. '
                'Please retry.',
              );
            }
          }
        }

        if (allowRetry && await _refreshClientForRegionalBucket(error)) {
          _logUpload('Retrying after refreshing secure-storage routing.');
          attempt = 0;
          continue;
        }

        if (!isLastAttempt) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          continue;
        }

        _rethrowAsConfigurationIfApplicable(error: error);
        if (proxyFirstError != null) {
          throw const WasabiStorageException(
            'Storage upload failed through both available paths. Please retry.',
          );
        }
        throw const WasabiStorageException(
          'Storage upload failed. Please retry.',
        );
      }
    }
  }

  Future<WasabiUploadResult> _uploadBufferedBytesViaProxy({
    required String objectKey,
    required Uint8List bytes,
    String? contentType,
  }) async {
    final tokenProvider = _browserUploadIdTokenProvider;
    if (tokenProvider == null) {
      throw const WasabiStorageException(
        'Browser upload fallback is not configured.',
      );
    }

    final token = await tokenProvider();
    if (token == null || token.trim().isEmpty) {
      throw const WasabiStorageException(
        'Browser upload fallback could not get a Firebase session token.',
      );
    }

    final uri =
        _browserUploadProxyUri ??
        ReleaseRuntimeConfig.resolveCheckoutApiBaseUri().resolve(
          'storage/wasabi/proxy-upload',
        );
    final response = await _httpClient
        .post(
          uri,
          headers: <String, String>{
            'Authorization': 'Bearer ${token.trim()}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'objectKey': objectKey,
            'contentType': contentType ?? 'application/octet-stream',
            'bytesBase64': base64Encode(bytes),
          }),
        )
        .timeout(const Duration(seconds: 90));

    final decoded = _decodeJsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WasabiStorageException(
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.storageTransfer,
          code: _proxyErrorCode(decoded),
          httpStatus: response.statusCode,
        ),
      );
    }

    return WasabiUploadResult(
      objectKey: objectKey,
      bucket: decoded?['bucket'] is String
          ? decoded!['bucket'] as String
          : bucket,
      eTag: decoded?['eTag'] is String ? decoded!['eTag'] as String : null,
    );
  }

  bool _shouldTryDownloadProxyFallback(Object error) {
    if (_browserUploadIdTokenProvider == null) {
      return false;
    }
    if (error is WasabiConfigurationException) {
      return true;
    }
    final description = error.toString();
    return description.contains('SignatureDoesNotMatch') ||
        description.contains('AuthorizationHeaderMalformed') ||
        description.contains('PermanentRedirect') ||
        description.contains('Wasabi storage is not configured') ||
        description.contains('Secure storage is not configured') ||
        description.contains('403') ||
        description.contains('Forbidden') ||
        description.contains('AccessDenied') ||
        description.contains('Access Denied') ||
        description.contains('XMLHttpRequest error') ||
        description.contains('Failed to fetch') ||
        description.contains('NetworkError');
  }

  Future<Uint8List> _downloadBufferedBytesViaProxy({
    required String objectKey,
    int? maxEncryptedBytes,
  }) async {
    final tokenProvider = _browserUploadIdTokenProvider;
    if (tokenProvider == null) {
      throw const WasabiStorageException(
        'Download fallback is not configured.',
      );
    }

    final token = await tokenProvider();
    if (token == null || token.trim().isEmpty) {
      throw const WasabiStorageException(
        'Download fallback could not get a Firebase session token.',
      );
    }

    final uri =
        _browserDownloadProxyUri ??
        ReleaseRuntimeConfig.resolveCheckoutApiBaseUri().resolve(
          'storage/wasabi/proxy-download',
        );
    final request = http.Request('POST', uri)
      ..headers.addAll(<String, String>{
        'Authorization': 'Bearer ${token.trim()}',
        'Content-Type': 'application/json',
      })
      ..body = jsonEncode(<String, dynamic>{'objectKey': objectKey});
    final response = await _httpClient
        .send(request)
        .timeout(const Duration(seconds: 90));

    final maxResponseBytes = maxEncryptedBytes == null
        ? null
        : (((maxEncryptedBytes + 2) ~/ 3) * 4) + 4096;
    final responseBytes = await _streamToBytes(
      response.stream,
      maxBytes: maxResponseBytes,
    );
    String responseBody;
    try {
      responseBody = utf8.decode(responseBytes);
    } on FormatException {
      throw const WasabiStorageException(
        'Download fallback returned an invalid response.',
      );
    }
    final decoded = _decodeJsonObject(responseBody);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WasabiStorageException(
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.storageTransfer,
          code: _proxyErrorCode(decoded),
          httpStatus: response.statusCode,
        ),
      );
    }

    final rawBytes = decoded?['bytesBase64'];
    if (rawBytes is! String || rawBytes.trim().isEmpty) {
      throw const WasabiStorageException(
        'Download fallback returned no file bytes.',
      );
    }
    try {
      final bytes = base64Decode(rawBytes);
      if (maxEncryptedBytes != null && bytes.length > maxEncryptedBytes) {
        throw const WasabiDownloadLimitException();
      }
      return bytes;
    } on FormatException {
      throw const WasabiStorageException(
        'Secure storage returned invalid encrypted file bytes.',
      );
    }
  }

  Map<String, dynamic>? _decodeJsonObject(String body) {
    if (body.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  String? _proxyErrorCode(Map<String, dynamic>? decoded) {
    final error = decoded?['error'];
    if (error is Map<String, dynamic>) {
      final status = error['status'];
      if (status is String && status.trim().isNotEmpty) {
        return status.trim();
      }
    }
    final status = decoded?['status'];
    if (status is String && status.trim().isNotEmpty) {
      return status.trim();
    }
    return null;
  }

  Future<WasabiUploadResult> _uploadMultipartStream({
    required String objectKey,
    required Stream<List<int>> stream,
    String? contentType,
    required bool allowRetry,
    String? transferId,
    MultipartUploadCheckpointSink? checkpointSink,
  }) async {
    String? uploadId;
    try {
      uploadId = await _createMultipartUpload(
        objectKey: objectKey,
        contentType: contentType,
        allowRetry: allowRetry,
      );
      if (transferId != null && checkpointSink != null) {
        await _recordMultipartCheckpoint(
          () => checkpointSink.multipartCreated(
            transferId: transferId,
            objectKey: objectKey,
            uploadId: uploadId!,
          ),
        );
      }
      final completedParts = await _uploadMultipartParts(
        objectKey: objectKey,
        uploadId: uploadId,
        stream: stream,
        allowRetry: allowRetry,
        transferId: transferId,
        checkpointSink: checkpointSink,
      );
      final response = await _completeMultipartUpload(
        objectKey: objectKey,
        uploadId: uploadId,
        parts: completedParts,
        allowRetry: allowRetry,
      );
      if (transferId != null && checkpointSink != null) {
        await _recordMultipartCheckpoint(
          () => checkpointSink.multipartCompleted(transferId: transferId),
        );
      }
      return WasabiUploadResult(
        objectKey: objectKey,
        bucket: bucket,
        eTag: response.eTag,
      );
    } catch (error) {
      if (uploadId != null) {
        try {
          await _abortMultipartUpload(objectKey: objectKey, uploadId: uploadId);
          if (transferId != null && checkpointSink != null) {
            await _recordMultipartCheckpoint(
              () => checkpointSink.multipartAborted(transferId: transferId),
            );
          }
        } catch (cleanupError) {
          if (transferId != null && checkpointSink != null) {
            await _recordMultipartCheckpoint(
              () => checkpointSink.multipartCleanupRequired(
                transferId: transferId,
                error: cleanupError,
              ),
            );
          }
        }
      }
      _rethrowAsConfigurationIfApplicable(error: error);
      throw const WasabiStorageException(
        'Storage upload failed. Please retry.',
      );
    }
  }

  Future<String> _createMultipartUpload({
    required String objectKey,
    String? contentType,
    required bool allowRetry,
  }) async {
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        final client = _client;
        if (client == null) {
          throw const WasabiConfigurationException(
            'Secure storage is not configured. Refresh account storage access.',
          );
        }
        final response = await client.createMultipartUpload(
          bucket: bucket,
          key: objectKey,
          contentType: contentType ?? 'application/octet-stream',
        );
        final uploadId = response.uploadId;
        if (uploadId == null || uploadId.isEmpty) {
          throw const WasabiStorageException(
            'Secure storage did not start the multipart upload.',
          );
        }
        return uploadId;
      } catch (error) {
        final isLastAttempt = attempt >= _maxUploadAttempts;
        if (allowRetry && await _refreshClientForRegionalBucket(error)) {
          attempt = 0;
          continue;
        }
        if (!isLastAttempt) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          continue;
        }
        rethrow;
      }
    }
  }

  Future<List<s3.CompletedPart>> _uploadMultipartParts({
    required String objectKey,
    required String uploadId,
    required Stream<List<int>> stream,
    required bool allowRetry,
    String? transferId,
    MultipartUploadCheckpointSink? checkpointSink,
  }) async {
    final completedParts = <s3.CompletedPart>[];
    var builder = BytesBuilder(copy: false);
    var bufferedLength = 0;
    var partNumber = 1;
    final pendingBatch = <({int partNumber, Uint8List bytes})>[];

    Future<void> flushBatch() async {
      if (pendingBatch.isEmpty) {
        return;
      }

      final currentBatch = List<({int partNumber, Uint8List bytes})>.from(
        pendingBatch,
        growable: false,
      );
      pendingBatch.clear();
      final uploadedParts = await Future.wait(
        currentBatch.map((part) async {
          final eTag = await _uploadMultipartPart(
            objectKey: objectKey,
            uploadId: uploadId,
            partNumber: part.partNumber,
            bytes: part.bytes,
            allowRetry: allowRetry,
          );
          if (transferId != null && checkpointSink != null) {
            await _recordMultipartCheckpoint(
              () => checkpointSink.multipartPartCompleted(
                transferId: transferId,
                partNumber: part.partNumber,
                eTag: eTag ?? '',
                uploadedBytes: part.bytes.length,
              ),
            );
          }
          return s3.CompletedPart(eTag: eTag, partNumber: part.partNumber);
        }),
      );
      completedParts.addAll(uploadedParts);
    }

    Future<void> flushPart() async {
      if (bufferedLength == 0) {
        return;
      }
      if (partNumber > 10000) {
        throw const WasabiStorageException(
          'Multipart upload exceeded the 10,000 part limit.',
        );
      }
      final partBytes = builder.takeBytes();
      builder = BytesBuilder(copy: false);
      bufferedLength = 0;
      pendingBatch.add((partNumber: partNumber, bytes: partBytes));
      partNumber++;
      if (pendingBatch.length >= _multipartUploadParallelism) {
        await flushBatch();
      }
    }

    await for (final chunk in stream) {
      var offset = 0;
      while (offset < chunk.length) {
        final remainingCapacity =
            _multipartUploadPartSizeBytes - bufferedLength;
        final bytesToCopy = remainingCapacity < chunk.length - offset
            ? remainingCapacity
            : chunk.length - offset;
        if (offset == 0 && bytesToCopy == chunk.length && bufferedLength == 0) {
          builder.add(chunk);
        } else {
          builder.add(chunk.sublist(offset, offset + bytesToCopy));
        }
        bufferedLength += bytesToCopy;
        offset += bytesToCopy;
        if (bufferedLength == _multipartUploadPartSizeBytes) {
          await flushPart();
        }
      }
    }

    await flushPart();
    await flushBatch();
    return completedParts;
  }

  Future<String?> _uploadMultipartPart({
    required String objectKey,
    required String uploadId,
    required int partNumber,
    required Uint8List bytes,
    required bool allowRetry,
  }) async {
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        final client = _client;
        if (client == null) {
          throw const WasabiConfigurationException(
            'Secure storage is not configured. Refresh account storage access.',
          );
        }
        if (kIsWeb) {
          final response = await putWasabiObjectViaBrowser(
            endpointUrl: endpointUrl,
            bucket: bucket,
            objectKey: objectKey,
            bytes: bytes,
            contentType: 'application/octet-stream',
            accessKey: accessKey,
            secretKey: secretKey,
            signingRegion: signingRegion,
            sessionToken: _sessionToken,
            queryParameters: <String, String>{
              'partNumber': partNumber.toString(),
              'uploadId': uploadId,
            },
          );
          return response.eTag;
        } else {
          final response = await client.uploadPart(
            bucket: bucket,
            key: objectKey,
            uploadId: uploadId,
            partNumber: partNumber,
            body: bytes,
            contentLength: bytes.length,
          );
          return response.eTag;
        }
      } catch (error) {
        final isLastAttempt = attempt >= _maxUploadAttempts;
        if (allowRetry && await _refreshClientForRegionalBucket(error)) {
          attempt = 0;
          continue;
        }
        if (!isLastAttempt) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          continue;
        }
        rethrow;
      }
    }
  }

  Future<s3.CompleteMultipartUploadOutput> _completeMultipartUpload({
    required String objectKey,
    required String uploadId,
    required List<s3.CompletedPart> parts,
    required bool allowRetry,
  }) async {
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        final client = _client;
        if (client == null) {
          throw const WasabiConfigurationException(
            'Secure storage is not configured. Refresh account storage access.',
          );
        }
        return await client.completeMultipartUpload(
          bucket: bucket,
          key: objectKey,
          uploadId: uploadId,
          multipartUpload: s3.CompletedMultipartUpload(parts: parts),
        );
      } catch (error) {
        final isLastAttempt = attempt >= _maxUploadAttempts;
        if (allowRetry && await _refreshClientForRegionalBucket(error)) {
          attempt = 0;
          continue;
        }
        if (!isLastAttempt) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          continue;
        }
        rethrow;
      }
    }
  }

  Future<void> _abortMultipartUpload({
    required String objectKey,
    required String uploadId,
  }) async {
    final client = _client;
    if (client == null) {
      return;
    }
    await client.abortMultipartUpload(
      bucket: bucket,
      key: objectKey,
      uploadId: uploadId,
    );
  }

  @override
  Future<void> cleanupInterruptedMultipartUpload({
    required String objectKey,
    required String uploadId,
  }) async {
    if (objectKey.trim().isEmpty || uploadId.trim().isEmpty) {
      throw const WasabiStorageException(
        'An object key and multipart upload id are required for cleanup.',
      );
    }
    await _abortMultipartUpload(objectKey: objectKey, uploadId: uploadId);
  }

  Future<void> _recordMultipartCheckpoint(
    Future<void> Function() callback,
  ) async {
    try {
      await callback();
    } catch (_) {
      _logUpload('A multipart transfer checkpoint could not be persisted.');
    }
  }

  @override
  @Deprecated('Use upload() instead. This method is not memory-efficient.')
  Future<WasabiUploadResult> uploadBytes({
    required String objectKey,
    required Uint8List bytes,
    String? contentType,
    SecretKey? encryptionKey,
    bool payloadAlreadyEncrypted = false,
    bool allowRetry = true,
  }) async {
    if (encryptionKey != null && payloadAlreadyEncrypted) {
      throw const WasabiStorageException(
        'Upload protection is ambiguous. Provide an encryption key or mark '
        'the payload as already encrypted, but not both.',
      );
    }
    if (encryptionKey == null && !payloadAlreadyEncrypted) {
      throw const WasabiStorageException(
        'Upload blocked because client-side encryption was not provided.',
      );
    }
    if (encryptionKey != null) {
      return upload(
        objectKey: objectKey,
        stream: Stream.value(bytes).cast<List<int>>(),
        length: bytes.length,
        contentType: contentType,
        encryptionKey: encryptionKey,
      );
    }
    return _uploadStream(
      objectKey: objectKey,
      stream: Stream.value(bytes).cast<List<int>>(),
      length: bytes.length,
      contentType: 'application/octet-stream',
      allowRetry: allowRetry,
    );
  }

  @override
  Future<Stream<List<int>>> download({
    required String objectKey,
    SecretKey? encryptionKey,
    bool preferProxy = false,
    int? maxPlaintextBytes,
  }) async {
    if (maxPlaintextBytes != null && maxPlaintextBytes <= 0) {
      throw const WasabiStorageException(
        'The local download buffer limit is invalid.',
      );
    }
    final algorithm = EncryptionService.instance.fileContentAlgorithm;
    final maxEncryptedBytes = maxPlaintextBytes == null
        ? null
        : maxPlaintextBytes +
              (encryptionKey == null
                  ? 0
                  : algorithm.nonceLength + algorithm.macAlgorithm.macLength);
    if (_isServerManagedObject(objectKey)) {
      return _downloadAuthorizedObject(
        objectKey: objectKey,
        encryptionKey: encryptionKey,
        maxPlaintextBytes: maxPlaintextBytes,
        bufferEncryptedPayload: kIsWeb || preferProxy,
      );
    }
    if (preferProxy && _browserUploadIdTokenProvider != null) {
      try {
        final bytes = await _downloadBufferedBytesViaProxy(
          objectKey: objectKey,
          maxEncryptedBytes: maxEncryptedBytes,
        );
        if (encryptionKey == null) {
          return Stream.value(bytes);
        }
        final plainBytes = await _decryptBufferedPayload(
          bytes: bytes,
          encryptionKey: encryptionKey,
        );
        if (maxPlaintextBytes != null &&
            plainBytes.length > maxPlaintextBytes) {
          throw const WasabiDownloadLimitException();
        }
        return Stream.value(plainBytes);
      } catch (error) {
        if (error is WasabiDownloadLimitException) {
          rethrow;
        }
        if (kDebugMode) {
          _logUpload('The protected download path was unavailable.');
        }
      }
    }

    try {
      return await _downloadDirect(
        objectKey: objectKey,
        encryptionKey: encryptionKey,
        maxPlaintextBytes: maxPlaintextBytes,
      );
    } catch (error) {
      if (!_shouldTryDownloadProxyFallback(error)) {
        rethrow;
      }
      try {
        final bytes = await _downloadBufferedBytesViaProxy(
          objectKey: objectKey,
          maxEncryptedBytes: maxEncryptedBytes,
        );
        if (encryptionKey == null) {
          return Stream.value(bytes);
        }
        final plainBytes = await _decryptBufferedPayload(
          bytes: bytes,
          encryptionKey: encryptionKey,
        );
        if (maxPlaintextBytes != null &&
            plainBytes.length > maxPlaintextBytes) {
          throw const WasabiDownloadLimitException();
        }
        return Stream.value(plainBytes);
      } catch (proxyError) {
        if (proxyError is WasabiDownloadLimitException) {
          rethrow;
        }
        throw const WasabiStorageException(
          'Storage download failed through both available paths. Please retry.',
        );
      }
    }
  }

  Future<http.StreamedResponse> _authorizedGet(Uri uri, {String? range}) async {
    final request = http.Request('GET', uri);
    if (range != null) {
      request.headers['Range'] = range;
    }
    final response = await _httpClient
        .send(request)
        .timeout(const Duration(minutes: 5));
    if (response.statusCode != 200 && response.statusCode != 206) {
      await response.stream.drain<void>();
      throw WasabiStorageException(
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.storageTransfer,
          httpStatus: response.statusCode,
        ),
      );
    }
    return response;
  }

  int? _authorizedObjectLength(http.StreamedResponse response) {
    final contentRange = response.headers['content-range'];
    final rangeMatch = contentRange == null
        ? null
        : RegExp(r'/([0-9]+)$').firstMatch(contentRange);
    final rangedLength = rangeMatch == null
        ? null
        : int.tryParse(rangeMatch.group(1)!);
    return rangedLength ??
        int.tryParse(response.headers['content-length'] ?? '');
  }

  Stream<List<int>> _boundedDownloadStream(
    Stream<List<int>> source,
    int? maxBytes,
  ) async* {
    if (maxBytes == null) {
      yield* source;
      return;
    }
    var received = 0;
    await for (final chunk in source) {
      if (received + chunk.length > maxBytes) {
        throw const WasabiDownloadLimitException();
      }
      received += chunk.length;
      yield chunk;
    }
  }

  Future<Stream<List<int>>> _downloadAuthorizedObject({
    required String objectKey,
    SecretKey? encryptionKey,
    int? maxPlaintextBytes,
    bool bufferEncryptedPayload = false,
  }) async {
    final authorization = await _authorizeServerManagedObject(
      objectKey: objectKey,
      action: 'get',
    );
    final uri = Uri.parse(authorization['url'] as String);
    if (encryptionKey == null) {
      final response = await _authorizedGet(
        uri,
        range: maxPlaintextBytes == null ? null : 'bytes=0-$maxPlaintextBytes',
      );
      final objectLength = _authorizedObjectLength(response);
      if (maxPlaintextBytes != null &&
          objectLength != null &&
          objectLength > maxPlaintextBytes) {
        await response.stream.drain<void>();
        throw const WasabiDownloadLimitException();
      }
      return _boundedDownloadStream(response.stream, maxPlaintextBytes);
    }

    final algorithm = EncryptionService.instance.fileContentAlgorithm;
    final nonceLength = algorithm.nonceLength;
    final macLength = algorithm.macAlgorithm.macLength;
    if (bufferEncryptedPayload) {
      // Web consumers already buffer the file. One GET avoids three serial
      // range requests and uses the browser's native authenticated decryption
      // instead of the Dart streaming fallback. Never expose unverified bytes.
      final maxEncryptedBytes = maxPlaintextBytes == null
          ? null
          : maxPlaintextBytes + nonceLength + macLength;
      final response = await _authorizedGet(
        uri,
        range: maxEncryptedBytes == null ? null : 'bytes=0-$maxEncryptedBytes',
      );
      final contentLength = _authorizedObjectLength(response);
      if (maxEncryptedBytes != null &&
          contentLength != null && contentLength > maxEncryptedBytes) {
        await response.stream.drain<void>();
        throw const WasabiDownloadLimitException();
      }
      final encrypted = await _streamToBytes(
        response.stream,
        maxBytes: maxEncryptedBytes,
      );
      final plaintext = await _decryptBufferedPayload(
        bytes: encrypted,
        encryptionKey: encryptionKey,
      );
      return Stream<List<int>>.value(plaintext);
    }
    final nonceResponse = await _authorizedGet(
      uri,
      range: 'bytes=0-${nonceLength - 1}',
    );
    final contentLength = _authorizedObjectLength(nonceResponse);
    if (contentLength == null || contentLength < nonceLength + macLength) {
      await nonceResponse.stream.drain<void>();
      throw const WasabiStorageException(
        'Storage returned an invalid encrypted object length.',
      );
    }
    final maxEncryptedBytes = maxPlaintextBytes == null
        ? null
        : maxPlaintextBytes + nonceLength + macLength;
    if (maxEncryptedBytes != null && contentLength > maxEncryptedBytes) {
      await nonceResponse.stream.drain<void>();
      throw const WasabiDownloadLimitException();
    }
    final nonce = await _streamToBytes(nonceResponse.stream);
    if (nonce.length != nonceLength) {
      throw const WasabiStorageException(
        'Failed to retrieve the encrypted file nonce.',
      );
    }
    final macResponse = await _authorizedGet(
      uri,
      range: 'bytes=${contentLength - macLength}-',
    );
    final macBytes = await _streamToBytes(macResponse.stream);
    if (macBytes.length != macLength) {
      throw const WasabiStorageException(
        'Failed to retrieve the encrypted file MAC.',
      );
    }
    final cipherStart = nonceLength;
    final cipherEnd = contentLength - macLength - 1;
    final cipherStream = cipherStart > cipherEnd
        ? Stream<List<int>>.value(const <int>[])
        : (await _authorizedGet(
            uri,
            range: 'bytes=$cipherStart-$cipherEnd',
          )).stream;
    return _boundedDownloadStream(
      algorithm.decryptStream(
        cipherStream,
        secretKey: encryptionKey,
        nonce: nonce,
        mac: Mac(macBytes),
      ),
      maxPlaintextBytes,
    );
  }

  Future<Stream<List<int>>> _downloadDirect({
    required String objectKey,
    SecretKey? encryptionKey,
    int? maxPlaintextBytes,
  }) async {
    final client = _client;
    if (client == null) {
      throw const WasabiConfigurationException(
        'Secure storage is not configured. Refresh account storage access.',
      );
    }

    if (encryptionKey == null) {
      return _boundedDownloadStream(
        await _downloadStream(objectKey: objectKey),
        maxPlaintextBytes,
      );
    }

    try {
      final headResponse = await client.headObject(
        bucket: bucket,
        key: objectKey,
      );
      final contentLength = headResponse.contentLength;
      if (contentLength == null) {
        throw const WasabiStorageException(
          'Could not determine file size for decryption.',
        );
      }

      final algorithm = EncryptionService.instance.fileContentAlgorithm;
      final macLength = algorithm.macAlgorithm.macLength;
      final nonceLength = algorithm.nonceLength;
      final minSize = macLength + nonceLength;

      if (contentLength < minSize) {
        throw const WasabiStorageException(
          'File is too small to be encrypted.',
        );
      }
      final maxEncryptedBytes = maxPlaintextBytes == null
          ? null
          : maxPlaintextBytes + nonceLength + macLength;
      if (maxEncryptedBytes != null && contentLength > maxEncryptedBytes) {
        throw const WasabiDownloadLimitException();
      }

      final nonceResponse = await client.getObject(
        bucket: bucket,
        key: objectKey,
        range: 'bytes=0-${nonceLength - 1}',
      );
      final Object? rawNonceBody = nonceResponse.body;
      Uint8List nonce;
      if (rawNonceBody is Uint8List) {
        nonce = rawNonceBody;
      } else if (rawNonceBody is Stream<List<int>>) {
        nonce = await _streamToBytes(rawNonceBody);
      } else {
        throw const WasabiStorageException(
          'Failed to retrieve file nonce: unsupported body type.',
        );
      }

      final macResponse = await client.getObject(
        bucket: bucket,
        key: objectKey,
        range: 'bytes=${contentLength - macLength}-',
      );
      final Object? rawMacBody = macResponse.body;
      Uint8List macBytes;
      if (rawMacBody is Uint8List) {
        macBytes = rawMacBody;
      } else if (rawMacBody is Stream<List<int>>) {
        macBytes = await _streamToBytes(rawMacBody);
      } else {
        throw const WasabiStorageException(
          'Failed to retrieve file MAC: unsupported body type.',
        );
      }
      final mac = Mac(macBytes);

      final cipherStart = nonceLength;
      final cipherEnd = contentLength - macLength - 1;

      Stream<List<int>> cipherStream;
      if (cipherStart > cipherEnd) {
        cipherStream = Stream.value([]);
      } else {
        final cipherResponse = await client.getObject(
          bucket: bucket,
          key: objectKey,
          range: 'bytes=$cipherStart-$cipherEnd',
        );
        final Object? rawCBody = cipherResponse.body;
        if (rawCBody is Uint8List) {
          cipherStream = Stream.value(rawCBody);
        } else if (rawCBody is Stream<List<int>>) {
          cipherStream = rawCBody;
        } else {
          throw const WasabiStorageException(
            'Failed to retrieve ciphertext: unsupported body type.',
          );
        }
      }

      return _boundedDownloadStream(
        algorithm.decryptStream(
          cipherStream,
          secretKey: encryptionKey,
          nonce: nonce,
          mac: mac,
        ),
        maxPlaintextBytes,
      );
    } catch (error) {
      if (error is WasabiDownloadLimitException) {
        rethrow;
      }
      _rethrowAsConfigurationIfApplicable(error: error);
      throw const WasabiStorageException(
        'Storage download failed. Please retry.',
      );
    }
  }

  Future<Uint8List> _decryptBufferedPayload({
    required Uint8List bytes,
    required SecretKey encryptionKey,
  }) async {
    final algorithm = EncryptionService.instance.fileContentAlgorithm;
    final macLength = algorithm.macAlgorithm.macLength;
    final nonceLength = algorithm.nonceLength;
    final minSize = macLength + nonceLength;
    if (bytes.length < minSize) {
      throw const WasabiStorageException('File is too small to be encrypted.');
    }
    final nonce = bytes.sublist(0, nonceLength);
    final cipherText = bytes.sublist(nonceLength, bytes.length - macLength);
    final mac = Mac(bytes.sublist(bytes.length - macLength));
    final plainBytes = await algorithm.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: encryptionKey,
    );
    return Uint8List.fromList(plainBytes);
  }

  Future<Uint8List> _encryptBufferedPayload({
    required Uint8List bytes,
    required SecretKey encryptionKey,
  }) async {
    _logUpload('Encrypting a buffered payload on this device.');
    final algorithm = EncryptionService.instance.fileContentAlgorithm;
    final nonce = algorithm.newNonce();
    final secretBox = await algorithm.encrypt(
      bytes,
      secretKey: encryptionKey,
      nonce: nonce,
    );
    final combined = Uint8List(
      secretBox.nonce.length +
          secretBox.cipherText.length +
          secretBox.mac.bytes.length,
    );
    var offset = 0;
    combined.setAll(offset, secretBox.nonce);
    offset += secretBox.nonce.length;
    combined.setAll(offset, secretBox.cipherText);
    offset += secretBox.cipherText.length;
    combined.setAll(offset, secretBox.mac.bytes);
    _logUpload('Buffered client-side encryption finished.');
    return combined;
  }

  Future<Uint8List> _streamToBytes(
    Stream<List<int>> stream, {
    int? maxBytes,
  }) async {
    if (maxBytes != null && maxBytes <= 0) {
      throw const WasabiStorageException(
        'The local download buffer limit is invalid.',
      );
    }
    final builder = BytesBuilder(copy: false);
    var chunkCount = 0;
    await for (final chunk in stream) {
      if (maxBytes != null && builder.length + chunk.length > maxBytes) {
        throw const WasabiDownloadLimitException();
      }
      builder.add(chunk);
      chunkCount++;
      if (kDebugMode && (chunkCount == 1 || chunkCount % 128 == 0)) {
        _logUpload('Buffered encrypted stream progress advanced.');
      }
    }
    if (kDebugMode) {
      _logUpload('Finished buffering an encrypted stream.');
    }
    return builder.takeBytes();
  }

  Future<Stream<List<int>>> _downloadStream({
    required String objectKey,
    bool allowRetry = true,
  }) async {
    final client = _client;
    if (client == null) {
      throw const WasabiConfigurationException(
        'Secure storage is not configured.',
      );
    }

    try {
      final response = await client.getObject(bucket: bucket, key: objectKey);

      final Object? body = response.body;
      if (body == null) {
        return const Stream.empty();
      }
      if (body is Stream<List<int>>) {
        return body;
      }
      throw const WasabiStorageException(
        'Secure storage returned an unsupported encrypted response.',
      );
    } catch (error) {
      if (allowRetry && await _refreshClientForRegionalBucket(error)) {
        return _downloadStream(objectKey: objectKey, allowRetry: false);
      }
      _rethrowAsConfigurationIfApplicable(error: error);
      throw const WasabiStorageException(
        'Storage download failed. Please retry.',
      );
    }
  }

  @override
  @Deprecated('Use download() instead. This method is not memory-efficient.')
  Future<Uint8List> downloadObject({
    required String objectKey,
    bool allowRetry = true,
    SecretKey? encryptionKey,
  }) async {
    final stream = await download(
      objectKey: objectKey,
      encryptionKey: encryptionKey,
    );
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  @override
  Future<void> deleteObject(String objectKey) async {
    if (_isServerManagedObject(objectKey)) {
      final authorization = await _authorizeServerManagedObject(
        objectKey: objectKey,
        action: 'delete',
      );
      final response = await _httpClient
          .delete(Uri.parse(authorization['url'] as String))
          .timeout(const Duration(seconds: 90));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw WasabiStorageException(
          userFacingCloudErrorMessage(
            operation: UserFacingCloudOperation.storageTransfer,
            httpStatus: response.statusCode,
          ),
        );
      }
      return;
    }
    final client = _client;
    if (client == null) {
      throw const WasabiConfigurationException(
        'Secure storage is not configured.',
      );
    }

    try {
      await client.deleteObject(bucket: bucket, key: objectKey);
    } catch (error) {
      if (await _refreshClientForRegionalBucket(error)) {
        return deleteObject(objectKey);
      }
      _rethrowAsConfigurationIfApplicable(error: error);
      throw const WasabiStorageException(
        'Storage deletion failed. Please retry.',
      );
    }
  }

  @override
  Future<Uint8List?> getObject(String objectKey) async {
    try {
      final stream = await download(objectKey: objectKey);
      return await _streamToBytes(stream);
    } catch (_) {
      _logUpload('Encrypted object reading was unavailable.');
      return null;
    }
  }

  Future<String> getPresignedUrl(
    String objectKey, {
    Duration duration = const Duration(hours: 1),
  }) async {
    if (_isServerManagedObject(objectKey)) {
      final authorization = await _authorizeServerManagedObject(
        objectKey: objectKey,
        action: 'get',
      );
      return authorization['url'] as String;
    }
    if (!_hasDirectCredentials) {
      throw const WasabiConfigurationException(
        'Direct storage links are unavailable for this account.',
      );
    }
    // Basic AWS Signature V4 Presigning
    final now = DateTime.now().toUtc();
    final expires = duration.inSeconds;
    final algorithm = 'AWS4-HMAC-SHA256';
    final service = 's3';

    final iso8601 =
        '${now.toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first}Z';
    final dateStamp = iso8601.substring(0, 8);

    final credentialScope = '$dateStamp/$signingRegion/$service/aws4_request';

    final queryParams = <String, String>{
      'X-Amz-Algorithm': algorithm,
      'X-Amz-Credential': '$accessKey/$credentialScope',
      'X-Amz-Date': iso8601,
      'X-Amz-Expires': expires.toString(),
      'X-Amz-SignedHeaders': 'host',
    };

    if (_sessionToken != null) {
      queryParams['X-Amz-Security-Token'] = _sessionToken;
    }

    final host = Uri.parse(endpointUrl).host;
    final canonicalUri = '/$bucket/${Uri.encodeComponent(objectKey)}';

    // Sort query params for canonical string
    final sortedKeys = queryParams.keys.toList()..sort();
    final sortedCanonicalQuerystring = sortedKeys
        .map(
          (key) =>
              '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(queryParams[key]!)}',
        )
        .join('&');

    final canonicalHeaders = 'host:$host\n';
    final signedHeaders = 'host';
    final payloadHash = 'UNSIGNED-PAYLOAD';

    final canonicalRequest =
        'GET\n$canonicalUri\n$sortedCanonicalQuerystring\n$canonicalHeaders\n$signedHeaders\n$payloadHash';

    final stringToSign =
        '$algorithm\n$iso8601\n$credentialScope\n${crypto.sha256.convert(utf8.encode(canonicalRequest))}';

    List<int> sign(List<int> key, String msg) {
      final hmac = crypto.Hmac(crypto.sha256, key);
      return hmac.convert(utf8.encode(msg)).bytes;
    }

    final kDate = sign(utf8.encode('AWS4$secretKey'), dateStamp);
    final kRegion = sign(kDate, signingRegion);
    final kService = sign(kRegion, service);
    final kSigning = sign(kService, 'aws4_request');
    final signature = crypto.Hmac(
      crypto.sha256,
      kSigning,
    ).convert(utf8.encode(stringToSign)).toString();

    return '$endpointUrl$canonicalUri?$sortedCanonicalQuerystring&X-Amz-Signature=$signature';
  }

  static String _sanitizeEndpoint(String endpoint) {
    final trimmed = endpoint.trim();
    if (trimmed.isEmpty) {
      return _defaultEndpoint;
    }

    final withoutTrailingSlash = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    if (withoutTrailingSlash.startsWith('http://') ||
        withoutTrailingSlash.startsWith('https://')) {
      return withoutTrailingSlash;
    }

    return 'https://$withoutTrailingSlash';
  }

  /// Normalizes [endpoint] so it targets the proper host for [region].
  ///
  /// Wasabi buckets that live outside of [_globalEndpointRegion] require the
  /// `s3.<region>.wasabisys.com` hostname even when the signing region remains
  /// us-east-1. This helper guarantees that behavior by rewriting the host
  /// whenever necessary. When [endpoint] is empty, the global Wasabi endpoint is
  /// returned so callers always receive a usable URL.
  static String _coerceEndpointForRegion(String endpoint, String region) {
    final sanitized = _sanitizeEndpoint(endpoint);
    final normalizedRegion = _normalizeRegionToken(region);
    if (normalizedRegion.isEmpty || normalizedRegion == _globalEndpointRegion) {
      return sanitized;
    }

    final uri = Uri.tryParse(sanitized);
    final host = (uri?.host.isNotEmpty ?? false) ? uri!.host : '';
    final normalizedHost = host.toLowerCase();
    final desiredHost = 's3.$normalizedRegion.wasabisys.com';
    final globalHost = Uri.parse(_defaultEndpoint).host.toLowerCase();

    if (normalizedHost == desiredHost) {
      return sanitized;
    }

    final shouldSwapHost =
        normalizedHost.isEmpty || normalizedHost == globalHost;
    if (!shouldSwapHost) {
      return sanitized;
    }

    final scheme = (uri?.scheme.isNotEmpty ?? false) ? uri!.scheme : 'https';
    return '$scheme://$desiredHost';
  }

  /// Builds the correct endpoint for [region], falling back to the global host
  /// when [region] is empty or refers to [_globalEndpointRegion].
  static String _buildRegionalEndpointFor(String region) {
    final normalized = _normalizeRegionToken(region);
    if (normalized.isEmpty || normalized == _globalEndpointRegion) {
      return _defaultEndpoint;
    }
    return 'https://s3.$normalized.wasabisys.com';
  }

  /// Returns a fully-qualified endpoint for [region]. When [endpointUrl] is
  /// provided, it will be coerced to the proper host for [region]; otherwise a
  /// region-specific endpoint will be synthesized.
  static String resolveEndpointForRegion({
    String? endpointUrl,
    String? region,
  }) {
    final normalizedRegion = _normalizeRegionToken(region ?? '');
    final trimmedEndpoint = endpointUrl?.trim() ?? '';
    if (trimmedEndpoint.isNotEmpty) {
      return _coerceEndpointForRegion(trimmedEndpoint, normalizedRegion);
    }
    return _buildRegionalEndpointFor(normalizedRegion);
  }

  static String _coerceSigningRegion(String candidate) {
    final normalized = _normalizeRegionToken(candidate);
    return normalized.isEmpty ? _globalEndpointRegion : normalized;
  }

  void _rethrowAsConfigurationIfApplicable({required Object error}) {
    final description = error.toString();
    final code = _extractErrorCode(description);

    if (_requiresRegionalEndpoint(description)) {
      throw const WasabiConfigurationException(
        'Secure storage needs a regional configuration refresh. Retry once, then contact support if it continues.',
      );
    }

    if (code == 'AuthorizationHeaderMalformed') {
      throw const WasabiConfigurationException(
        'Secure-storage authorization needs a configuration refresh. Retry once, then contact support if it continues.',
      );
    }

    if (code == 'PermanentRedirect') {
      throw const WasabiConfigurationException(
        'Secure storage needs a regional configuration refresh. Retry once, then contact support if it continues.',
      );
    }

    if (code == 'SignatureDoesNotMatch') {
      throw const WasabiConfigurationException(
        'Secure-storage authorization could not be verified. Refresh access and retry.',
      );
    }

    if (code == 'AccessDenied') {
      throw const WasabiConfigurationException(
        'This account is not authorized for the requested secure-storage object. Refresh access and retry.',
      );
    }

    if (_isPublicAccessBlocked(description)) {
      throw const WasabiConfigurationException(
        'Secure-storage policy rejected this operation. Contact support if it continues.',
      );
    }
  }

  String _extractErrorCode(String description) {
    if (description.contains('AuthorizationHeaderMalformed')) {
      return 'AuthorizationHeaderMalformed';
    }
    if (description.contains('PermanentRedirect')) {
      return 'PermanentRedirect';
    }
    if (description.contains('SignatureDoesNotMatch')) {
      return 'SignatureDoesNotMatch';
    }
    if (description.contains('AccessDenied') ||
        description.contains('Access Denied')) {
      return 'AccessDenied';
    }
    return '';
  }

  bool _isPublicAccessBlocked(String description) {
    return description.contains(
      'Public use of objects is not allowed by this account',
    );
  }

  bool _requiresRegionalEndpoint(String description) {
    return description.contains(
          'The bucket you are attempting to access must be addressed using the specified endpoint',
        ) ||
        description.contains(
          'Please send all future requests to this endpoint',
        );
  }

  Future<bool> _refreshClientForRegionalBucket(Object error) async {
    if (_client == null || bucket.isEmpty) {
      return false;
    }

    final description = error.toString();
    final code = _extractErrorCode(description);
    final requiresRegionalEndpoint = _requiresRegionalEndpoint(description);
    final shouldAttempt =
        requiresRegionalEndpoint ||
        code == 'PermanentRedirect' ||
        code == 'AuthorizationHeaderMalformed' ||
        code == 'SignatureDoesNotMatch';
    if (!shouldAttempt) {
      return false;
    }

    final redirectEndpoint = _extractRedirectEndpoint(description);
    if (redirectEndpoint != null &&
        await _updateClientEndpoint(redirectEndpoint)) {
      return true;
    }

    final lookedUpEndpoint = await _lookupEndpointFromBucketLocation();
    if (lookedUpEndpoint != null &&
        await _updateClientEndpoint(lookedUpEndpoint)) {
      return true;
    }

    if (requiresRegionalEndpoint &&
        _bucketRegion.isNotEmpty &&
        _bucketRegion != _globalEndpointRegion) {
      final derivedEndpoint = _buildRegionalEndpointFor(_bucketRegion);
      if (await _updateClientEndpoint(derivedEndpoint)) {
        return true;
      }
    }

    return false;
  }

  String? _extractRedirectEndpoint(String description) {
    const suffix = 'wasabisys.com';
    final hostIndex = description.indexOf(suffix);
    if (hostIndex == -1) {
      return null;
    }

    var start = hostIndex;
    while (start > 0) {
      final char = description[start - 1];
      final code = char.codeUnitAt(0);
      final isAlpha = (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
      final isDigit = code >= 48 && code <= 57;
      final isAllowed = isAlpha || isDigit || char == '.' || char == '-';
      if (!isAllowed) {
        break;
      }
      start -= 1;
    }

    final end = hostIndex + suffix.length;
    final host = description.substring(start, end);

    final schemeIndex = description.lastIndexOf('https://', start);
    if (schemeIndex != -1) {
      return description.substring(schemeIndex, end);
    }

    return 'https://$host';
  }

  Future<bool> _updateClientEndpoint(String endpoint) async {
    final sanitized = _coerceEndpointForRegion(endpoint, _bucketRegion);
    if (sanitized == _endpointUrl) {
      return false;
    }

    final derivedRegion = inferRegionFromEndpoint(sanitized);
    final credentials = s3.AwsClientCredentials(
      accessKey: _accessKey,
      secretKey: _secretKey,
      sessionToken: _sessionToken,
    );

    _client = s3.S3(
      region: signingRegion,
      credentials: credentials,
      endpointUrl: sanitized,
    );

    if (derivedRegion != null && derivedRegion.isNotEmpty) {
      _bucketRegion = derivedRegion;
    }
    _endpointUrl = sanitized;
    return true;
  }

  Future<String?> _lookupEndpointFromBucketLocation() async {
    if (_accessKey.isEmpty || _secretKey.isEmpty) {
      return null;
    }

    try {
      final lookupClient = s3.S3(
        region: signingRegion,
        credentials: s3.AwsClientCredentials(
          accessKey: _accessKey,
          secretKey: _secretKey,
          sessionToken: _sessionToken,
        ),
        endpointUrl: _defaultEndpoint,
      );
      final location = await lookupClient.getBucketLocation(bucket: bucket);
      final region = _coerceRegionFromLocationConstraint(
        location.locationConstraint,
      );
      if (region == null || region.isEmpty || region == _globalEndpointRegion) {
        return null;
      }
      return _buildRegionalEndpointFor(region);
    } catch (_) {
      return null;
    }
  }

  static String? inferRegionFromEndpoint(String endpoint) {
    final trimmed = endpoint.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(trimmed);
    final host = (uri?.host.isNotEmpty ?? false) ? uri!.host : trimmed;
    const prefix = 's3.';
    const suffix = '.wasabisys.com';
    if (!host.startsWith(prefix) || !host.endsWith(suffix)) {
      return null;
    }

    final minimumLength = prefix.length + suffix.length + 1; // region character
    if (host.length < minimumLength) {
      return null;
    }

    final region = host.substring(prefix.length, host.length - suffix.length);
    return region.isEmpty ? null : region;
  }

  String? _coerceRegionFromLocationConstraint(dynamic constraint) {
    if (constraint == null) {
      return _globalEndpointRegion;
    }

    if (constraint is String) {
      final normalized = _normalizeRegionToken(constraint);
      return normalized.isEmpty ? null : normalized;
    }

    final description = constraint.toString();
    if (description.isEmpty) {
      return null;
    }
    final segments = description.split('.');
    final raw = segments.isEmpty ? description : segments.last;
    final normalized = _normalizeRegionToken(raw);
    return normalized.isEmpty ? null : normalized;
  }

  static String _normalizeRegionToken(String value) {
    final trimmed = value.trim().replaceAll('_', '-');
    if (trimmed.isEmpty) {
      return '';
    }

    final buffer = StringBuffer();
    for (var i = 0; i < trimmed.length; i++) {
      final char = trimmed[i];
      final code = char.codeUnitAt(0);
      final isUpper = char.toUpperCase() == char && char.toLowerCase() != char;
      final isDigit = code >= 48 && code <= 57;
      if (i > 0) {
        final prev = trimmed[i - 1];
        final prevCode = prev.codeUnitAt(0);
        final prevIsDigit = prevCode >= 48 && prevCode <= 57;
        final prevIsHyphen = prev == '-';
        if (!prevIsHyphen && (isUpper || (isDigit && !prevIsDigit))) {
          buffer.write('-');
        }
      }
      buffer.write(char.toLowerCase());
    }

    return buffer.toString().replaceAll('--', '-');
  }
}
