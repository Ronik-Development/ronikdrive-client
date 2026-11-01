import 'dart:async';

import 'package:cloud_storage/src/share/public_transfer_failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('arbitrary failures never become public-link text', () {
    for (final action in PublicTransferAction.values) {
      final message = publicTransferFailureMessage(
        Exception(
          r'user@example.test C:\Users\person\private-photo.png token=secret',
        ),
        action: action,
      );
      expect(message, isNotEmpty);
      expect(message, isNot(contains('user@example.test')));
      expect(message, isNot(contains(r'C:\Users')));
      expect(message, isNot(contains('private-photo.png')));
      expect(message, isNot(contains('secret')));
    }
  });

  test('network failures use fixed action-specific recovery', () {
    expect(
      publicTransferFailureMessage(
        TimeoutException('https://private.example/path'),
        action: PublicTransferAction.uploadFile,
      ),
      allOf(contains('original file remains'), contains('connection')),
    );
    expect(
      publicTransferFailureMessage(
        http.ClientException('Bearer secret', Uri.parse('https://private')),
        action: PublicTransferAction.downloadShare,
      ),
      'The encrypted download could not be completed. Check your connection and retry.',
    );
  });

  test('typed file limits retain useful local guidance', () {
    expect(
      publicTransferFailureMessage(
        const PublicTransferException(
          PublicTransferFailureKind.selectedFileTooLarge,
          maximumBytes: 25 * 1024 * 1024,
        ),
        action: PublicTransferAction.uploadFile,
      ),
      'This request accepts files up to 25 MB.',
    );
  });

  test('HTTP status mapping exposes no response body', () {
    expect(
      publicTransferFailureMessage(
        const PublicTransferException(
          PublicTransferFailureKind.httpStatus,
          statusCode: 404,
        ),
        action: PublicTransferAction.openShare,
      ),
      contains('no longer exists'),
    );
    expect(
      const PublicTransferException(
        PublicTransferFailureKind.httpStatus,
        statusCode: 500,
      ).toString(),
      'PublicTransferException(httpStatus)',
    );
  });

  test('reserved request slots give temporary identity-free recovery', () {
    expect(
      publicTransferFailureMessage(
        const PublicTransferException(
          PublicTransferFailureKind.httpStatus,
          statusCode: 423,
        ),
        action: PublicTransferAction.openFileRequest,
      ),
      contains('released automatically'),
    );
    expect(
      publicTransferFailureMessage(
        const PublicTransferException(
          PublicTransferFailureKind.httpStatus,
          statusCode: 409,
        ),
        action: PublicTransferAction.uploadFile,
      ),
      contains('reached its upload limit'),
    );
  });
}
