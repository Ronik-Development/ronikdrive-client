import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:web/web.dart' as web;

class WasabiBrowserUploadResponse {
  const WasabiBrowserUploadResponse({required this.eTag});

  final String? eTag;
}

Future<WasabiBrowserUploadResponse> putWasabiObjectViaBrowser({
  required String endpointUrl,
  required String bucket,
  required String objectKey,
  required Uint8List bytes,
  required String contentType,
  required String accessKey,
  required String secretKey,
  required String signingRegion,
  String? sessionToken,
  Map<String, String> queryParameters = const <String, String>{},
}) async {
  final endpoint = endpointUrl.endsWith('/')
      ? endpointUrl.substring(0, endpointUrl.length - 1)
      : endpointUrl;
  final endpointUri = Uri.parse(endpoint);
  final host = endpointUri.host;
  final payloadHash = crypto.sha256.convert(bytes).toString();
  final now = DateTime.now().toUtc();
  final iso8601 =
      '${now.toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first}Z';
  final dateStamp = iso8601.substring(0, 8);
  final region = signingRegion.trim().isEmpty ? 'us-east-1' : signingRegion;
  const algorithm = 'AWS4-HMAC-SHA256';
  const service = 's3';
  final credentialScope = '$dateStamp/$region/$service/aws4_request';
  final canonicalUri =
      '/${_encodePathSegment(bucket)}/${_encodeS3Key(objectKey)}';
  final canonicalQuery = _canonicalQuery(queryParameters);

  final signedHeaderValues = <String, String>{
    'content-type': contentType.trim().isEmpty
        ? 'application/octet-stream'
        : contentType.trim(),
    'host': host,
    'x-amz-content-sha256': payloadHash,
    'x-amz-date': iso8601,
  };
  if (sessionToken != null && sessionToken.trim().isNotEmpty) {
    signedHeaderValues['x-amz-security-token'] = sessionToken.trim();
  }

  final signedHeaderNames = signedHeaderValues.keys.toList()..sort();
  final canonicalHeaders = signedHeaderNames
      .map(
        (name) => '$name:${_canonicalHeaderValue(signedHeaderValues[name]!)}\n',
      )
      .join();
  final signedHeaders = signedHeaderNames.join(';');
  final canonicalRequest =
      'PUT\n$canonicalUri\n$canonicalQuery\n$canonicalHeaders\n$signedHeaders\n$payloadHash';
  final stringToSign =
      '$algorithm\n$iso8601\n$credentialScope\n${crypto.sha256.convert(utf8.encode(canonicalRequest))}';
  final signature = _signature(
    secretKey: secretKey,
    dateStamp: dateStamp,
    region: region,
    service: service,
    stringToSign: stringToSign,
  );
  final authorization =
      '$algorithm Credential=$accessKey/$credentialScope, SignedHeaders=$signedHeaders, Signature=$signature';
  final url = canonicalQuery.isEmpty
      ? '$endpoint$canonicalUri'
      : '$endpoint$canonicalUri?$canonicalQuery';

  final requestHeaders = <String, String>{
    'Authorization': authorization,
    'Content-Type': signedHeaderValues['content-type']!,
    'x-amz-content-sha256': payloadHash,
    'x-amz-date': iso8601,
  };
  final token = signedHeaderValues['x-amz-security-token'];
  if (token != null) {
    requestHeaders['x-amz-security-token'] = token;
  }

  final xhr = await _sendBytes(url: url, headers: requestHeaders, bytes: bytes);
  return WasabiBrowserUploadResponse(
    eTag: _normalizeETag(xhr.getResponseHeader('ETag')),
  );
}

Future<web.XMLHttpRequest> _sendBytes({
  required String url,
  required Map<String, String> headers,
  required Uint8List bytes,
}) {
  final completer = Completer<web.XMLHttpRequest>();
  final xhr = web.XMLHttpRequest();
  xhr.open('PUT', url, true);
  headers.forEach((name, value) {
    xhr.setRequestHeader(name, value);
  });

  late final StreamSubscription<web.ProgressEvent> loadSubscription;
  late final StreamSubscription<web.ProgressEvent> errorSubscription;
  final timeoutTimer = Timer(const Duration(seconds: 60), () {
    if (!completer.isCompleted) {
      xhr.abort();
      completer.completeError(
        StateError('Wasabi browser upload timed out before a response.'),
      );
    }
  });
  loadSubscription = xhr.onLoad.listen((_) {
    final status = xhr.status;
    if (status >= 200 && status < 300) {
      if (!completer.isCompleted) {
        completer.complete(xhr);
      }
    } else if (!completer.isCompleted) {
      completer.completeError(
        StateError(
          'Wasabi browser upload failed with HTTP $status ${xhr.statusText}: ${xhr.responseText}',
        ),
      );
    }
  });
  errorSubscription = xhr.onError.listen((_) {
    if (!completer.isCompleted) {
      completer.completeError(
        StateError(
          'Wasabi browser upload failed before a response was returned. '
          'This usually means the browser blocked the request at CORS/preflight '
          'or network level. status=${xhr.status} ${xhr.statusText}',
        ),
      );
    }
  });
  completer.future.whenComplete(() async {
    timeoutTimer.cancel();
    await loadSubscription.cancel();
    await errorSubscription.cancel();
  });

  xhr.send(bytes.toJS);
  return completer.future;
}

String _canonicalQuery(Map<String, String> queryParameters) {
  if (queryParameters.isEmpty) {
    return '';
  }
  final keys = queryParameters.keys.toList()..sort();
  return keys
      .map(
        (key) =>
            '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(queryParameters[key] ?? '')}',
      )
      .join('&');
}

String _encodeS3Key(String key) {
  return key.split('/').map(_encodePathSegment).join('/');
}

String _encodePathSegment(String segment) {
  return Uri.encodeComponent(segment).replaceAll('%7E', '~');
}

String _canonicalHeaderValue(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ');
}

String _signature({
  required String secretKey,
  required String dateStamp,
  required String region,
  required String service,
  required String stringToSign,
}) {
  List<int> sign(List<int> key, String message) {
    return crypto.Hmac(crypto.sha256, key).convert(utf8.encode(message)).bytes;
  }

  final kDate = sign(utf8.encode('AWS4$secretKey'), dateStamp);
  final kRegion = sign(kDate, region);
  final kService = sign(kRegion, service);
  final kSigning = sign(kService, 'aws4_request');
  return crypto.Hmac(
    crypto.sha256,
    kSigning,
  ).convert(utf8.encode(stringToSign)).toString();
}

String? _normalizeETag(String? eTag) {
  if (eTag == null) {
    return null;
  }
  final trimmed = eTag.trim();
  return trimmed.isEmpty ? null : trimmed;
}
