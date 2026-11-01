import 'dart:math';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../shared/service_environment.dart';

typedef ShareEmailCallable =
    Future<Map<String, dynamic>> Function(
      String name,
      Map<String, Object> payload,
    );

String? normalizeShareRecipientEmail(String value) {
  final email = value.trim();
  final parts = email.split('@');
  if (email.length > 254 || parts.length != 2) return null;
  final local = parts.first;
  final domain = parts.last;
  if (local.isEmpty ||
      local.length > 64 ||
      local.startsWith('.') ||
      local.endsWith('.') ||
      local.contains('..') ||
      !RegExp(r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+$").hasMatch(local)) {
    return null;
  }
  final labels = domain.split('.');
  if (labels.length < 2 ||
      labels.any(
        (label) =>
            label.length > 63 ||
            !RegExp(
              r'^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$',
            ).hasMatch(label),
      )) {
    return null;
  }
  return '$local@${domain.toLowerCase()}';
}

bool isValidShareRecipientEmail(String value) =>
    normalizeShareRecipientEmail(value) != null;

String newShareEmailRequestId() {
  final random = Random.secure();
  return base64Url
      .encode(List.generate(24, (_) => random.nextInt(256)))
      .replaceAll('=', '');
}

class ShareEmailException implements Exception {
  const ShareEmailException(this.message);

  /// Always selected from fixed client text, never a provider response.
  final String message;
  @override
  String toString() => 'ShareEmailException';
}

/// Sends only a public token and one explicitly chosen address. There is no URL,
/// file label, password, content key, subject or free-form message parameter.
class ShareEmailService {
  ShareEmailService({
    required FirebaseAuth auth,
    required String ownerUid,
    ShareEmailCallable? callable,
  }) : _auth = auth,
       _ownerUid = ownerUid,
       _callable = callable;
  final FirebaseAuth _auth;
  final String _ownerUid;
  final ShareEmailCallable? _callable;

  void _checkOwner() {
    if (_auth.currentUser?.uid != _ownerUid) {
      throw const ShareEmailException(
        'Your sign-in changed. Open sharing again for the current account.',
      );
    }
  }

  Future<void> sendPasswordLink({
    required String shareToken,
    required String recipientEmail,
    required String requestId,
    required bool passwordProtected,
  }) async {
    _checkOwner();
    final normalizedRecipient = normalizeShareRecipientEmail(recipientEmail);
    if (!passwordProtected) {
      throw const ShareEmailException(
        'Use your email app to send a link without a separate password.',
      );
    }
    if (normalizedRecipient == null ||
        !RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(shareToken) ||
        !RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(requestId)) {
      throw const ShareEmailException(
        'Enter one valid recipient email address.',
      );
    }
    try {
      final callable = _callable;
      final payload = <String, Object>{
        'shareToken': shareToken,
        'recipientEmail': normalizedRecipient,
        'requestId': requestId,
      };
      final Map<String, dynamic> data;
      if (callable != null) {
        data = await callable(
          'sendShareLinkEmail',
          payload,
        ).timeout(const Duration(seconds: 30));
      } else {
        final result =
            await FirebaseFunctions.instanceFor(
                  app: _auth.app,
                  region: 'europe-west1',
                )
                .httpsCallable('sendShareLinkEmail')
                .call(payload)
                .timeout(const Duration(seconds: 30));
        if (result.data is! Map) throw const FormatException();
        data = Map<String, dynamic>.from(result.data as Map);
      }
      _checkOwner();
      if (data['accepted'] != true || data['status'] != 'accepted') {
        throw const FormatException();
      }
    } on ShareEmailException {
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      throw ShareEmailException(switch (error.code) {
        'unauthenticated' || 'permission-denied' =>
          'This link can no longer be emailed from this account. Check your access and open sharing again.',
        'failed-precondition' || 'not-found' =>
          'This link is no longer available for email. Check its expiry and access before retrying.',
        'resource-exhausted' =>
          'Email sharing is temporarily limited. Wait before retrying this send.',
        _ =>
          'Email acceptance could not be confirmed. Wait about a minute before retrying this send, or copy the link.',
      });
    } catch (_) {
      throw const ShareEmailException(
        'Email acceptance could not be confirmed. Wait about a minute before retrying this send, or copy the link.',
      );
    }
  }
}

Uri shareLinkMailto({
  required String recipientEmail,
  required Uri completeLink,
}) {
  final normalizedRecipient = normalizeShareRecipientEmail(recipientEmail);
  if (normalizedRecipient == null ||
      (completeLink.scheme != 'https' && completeLink.scheme != 'http') ||
      completeLink.userInfo.isNotEmpty ||
      completeLink.host.isEmpty) {
    throw const ShareEmailException('Enter one valid recipient email address.');
  }
  if (completeLink.scheme == 'http') {
    try {
      ServiceEnvironmentConfig.guardServiceUri(
        completeLink.replace(fragment: ''),
      );
    } catch (_) {
      throw const ShareEmailException(
        'This private link cannot be opened in an email app in this environment. Copy the complete link instead.',
      );
    }
  }
  final query =
      <String, String>{
            'subject': 'An encrypted file shared with you',
            'body':
                'Open this complete link to download the encrypted shared file:\n\n$completeLink\n\nAnyone with this complete link can open the file until it expires or is revoked. Share it only with people you trust.',
          }.entries
          .map(
            (entry) =>
                '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value)}',
          )
          .join('&');
  return Uri(scheme: 'mailto', path: normalizedRecipient, query: query);
}
