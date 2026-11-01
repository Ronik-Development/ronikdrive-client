import 'dart:async';

import 'package:http/http.dart' as http;

enum PublicTransferAction {
  openFileRequest,
  uploadFile,
  openShare,
  downloadShare,
}

enum PublicTransferFailureKind {
  missingPrivateKey,
  invalidPrivateKey,
  closedOrExpired,
  uploadLimitReached,
  recipientStorageFull,
  selectedFileUnreadable,
  selectedFileTooLarge,
  authorizationIncomplete,
  uploadRejected,
  responseIncomplete,
  unsupportedMetadata,
  unsupportedProtection,
  httpStatus,
}

class PublicTransferException implements Exception {
  const PublicTransferException(
    this.kind, {
    this.statusCode,
    this.maximumBytes,
  });

  final PublicTransferFailureKind kind;
  final int? statusCode;
  final int? maximumBytes;

  @override
  String toString() => 'PublicTransferException(${kind.name})';
}

String publicTransferFailureMessage(
  Object error, {
  required PublicTransferAction action,
}) {
  if (error is PublicTransferException) {
    return switch (error.kind) {
      PublicTransferFailureKind.missingPrivateKey =>
        'This link is missing its private encryption fragment. Ask the owner to copy the complete link again.',
      PublicTransferFailureKind.invalidPrivateKey =>
        'This link has an invalid private encryption key. Ask the owner for a new link.',
      PublicTransferFailureKind.closedOrExpired =>
        action == PublicTransferAction.openShare ||
                action == PublicTransferAction.downloadShare
            ? 'This share link has expired or was closed. Ask the sender for a new link.'
            : 'This file request is closed or expired. Ask the owner for a new link.',
      PublicTransferFailureKind.uploadLimitReached =>
        'This file request reached its upload limit. Ask the owner for a new request.',
      PublicTransferFailureKind.recipientStorageFull =>
        'The recipient does not have enough storage for this file. Ask them to free space or upgrade, then retry.',
      PublicTransferFailureKind.selectedFileUnreadable =>
        'The selected file could not be read in this browser. Choose it again or use the RonikCloud app.',
      PublicTransferFailureKind.selectedFileTooLarge =>
        error.maximumBytes != null && error.maximumBytes! > 0
            ? 'This request accepts files up to ${_formatBytes(error.maximumBytes!)}.'
            : 'The selected file is larger than this request allows.',
      PublicTransferFailureKind.authorizationIncomplete =>
        'Secure upload preparation was incomplete. No readable file data was sent. Retry shortly.',
      PublicTransferFailureKind.uploadRejected =>
        'The storage service did not accept the encrypted upload. Your original file remains on this device. Retry shortly.',
      PublicTransferFailureKind.responseIncomplete =>
        action == PublicTransferAction.openShare ||
                action == PublicTransferAction.downloadShare
            ? 'The encrypted shared-file response was incomplete. Retry shortly.'
            : 'The secure file-request response was incomplete. Retry shortly.',
      PublicTransferFailureKind.unsupportedMetadata =>
        action == PublicTransferAction.openShare ||
                action == PublicTransferAction.downloadShare
            ? 'This share uses unsupported encryption metadata. Ask the sender for a new link created by the current app.'
            : 'This file request uses unsupported encryption metadata. Ask the owner for a new link created by the current app.',
      PublicTransferFailureKind.unsupportedProtection =>
        'This share uses unsupported download protection. Ask the sender for a new link created by the current app.',
      PublicTransferFailureKind.httpStatus => _httpFailureMessage(
        error.statusCode,
        action,
      ),
    };
  }

  if (error is TimeoutException || error is http.ClientException) {
    return _connectionFailureMessage(action);
  }
  return _genericFailureMessage(action);
}

String _httpFailureMessage(int? statusCode, PublicTransferAction action) {
  if (statusCode == 404 || statusCode == 410) {
    return action == PublicTransferAction.openShare ||
            action == PublicTransferAction.downloadShare
        ? 'This shared file no longer exists or is unavailable. Ask the sender for a new link.'
        : 'This file request no longer exists or is closed. Ask the owner for a new link.';
  }
  if (statusCode == 401 || statusCode == 403) {
    return 'This private link is no longer authorized. Ask for a new link.';
  }
  if (statusCode == 413 && action == PublicTransferAction.uploadFile) {
    return 'The encrypted upload is larger than this request allows. Choose a smaller file.';
  }
  if (statusCode == 413 && action == PublicTransferAction.downloadShare) {
    return 'This shared file exceeds the 20 MiB link limit. Ask the sender for a smaller shared copy.';
  }
  if (statusCode == 409 &&
      (action == PublicTransferAction.openFileRequest ||
          action == PublicTransferAction.uploadFile)) {
    return 'This file request reached its upload limit. Ask the owner for a new request.';
  }
  if (statusCode == 423 &&
      (action == PublicTransferAction.openFileRequest ||
          action == PublicTransferAction.uploadFile)) {
    return 'Every remaining upload slot is currently in use. Unfinished attempts are released automatically; retry shortly.';
  }
  if (statusCode == 429) {
    return 'This private link is temporarily busy after too many requests. Wait briefly and retry.';
  }
  if (statusCode != null && statusCode >= 500) {
    return _connectionFailureMessage(action);
  }
  return _genericFailureMessage(action);
}

String _connectionFailureMessage(
  PublicTransferAction action,
) => switch (action) {
  PublicTransferAction.openFileRequest =>
    'This file request is temporarily unavailable. Check your connection and retry.',
  PublicTransferAction.uploadFile =>
    'The encrypted upload could not be completed. Your original file remains on this device. Check your connection and retry.',
  PublicTransferAction.openShare =>
    'This shared file is temporarily unavailable. Check your connection and retry.',
  PublicTransferAction.downloadShare =>
    'The encrypted download could not be completed. Check your connection and retry.',
};

String _genericFailureMessage(PublicTransferAction action) => switch (action) {
  PublicTransferAction.openFileRequest =>
    'This file request could not be opened. Check the complete link and retry.',
  PublicTransferAction.uploadFile =>
    'The encrypted upload could not be completed. Your original file remains on this device. Retry shortly.',
  PublicTransferAction.openShare =>
    'This shared file could not be opened. Check the complete link and retry.',
  PublicTransferAction.downloadShare =>
    'The encrypted download could not be completed. Retry shortly.',
};

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
  return '${(bytes / 1024).toStringAsFixed(0)} KB';
}
