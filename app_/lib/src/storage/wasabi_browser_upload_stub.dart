import 'dart:typed_data';

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
}) {
  throw UnsupportedError('Browser Wasabi uploads are only available on web.');
}
