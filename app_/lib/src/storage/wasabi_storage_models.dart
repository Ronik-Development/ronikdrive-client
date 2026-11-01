part of 'wasabi_storage_service.dart';

class WasabiUploadResult {
  const WasabiUploadResult({
    required this.objectKey,
    required this.bucket,
    this.eTag,
  });

  final String objectKey;
  final String bucket;
  final String? eTag;
}

class WasabiConfigurationException implements Exception {
  const WasabiConfigurationException(this.message);

  final String message;

  @override
  String toString() => 'WasabiConfigurationException: $message';
}

class WasabiStorageException implements Exception {
  const WasabiStorageException(this.message);

  final String message;

  @override
  String toString() => 'WasabiStorageException: $message';
}

class WasabiDownloadLimitException extends WasabiStorageException {
  const WasabiDownloadLimitException()
    : super('Storage returned more file data than expected.');
}
