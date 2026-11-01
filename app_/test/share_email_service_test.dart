import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_storage/src/share/share_email_service.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MockFirebaseAuth auth;
  late ShareEmailService service;
  late List<Map<String, Object>> requests;
  Object? failure;
  Completer<Map<String, dynamic>>? response;
  setUp(() {
    auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'synthetic-owner'),
      signedIn: true,
    );
    requests = [];
    failure = null;
    response = null;
    service = ShareEmailService(
      auth: auth,
      ownerUid: 'synthetic-owner',
      callable: (name, payload) async {
        expect(name, 'sendShareLinkEmail');
        requests.add(Map.of(payload));
        if (failure != null) throw failure!;
        return response?.future ??
            Future.value({'accepted': true, 'status': 'accepted'});
      },
    );
  });
  Future<void> send({
    bool protected = true,
    String email = 'Recipient+Tag@EXAMPLE.TEST',
  }) => service.sendPasswordLink(
    shareToken: 'synthetic-share-token-123',
    recipientEmail: email,
    requestId: 'synthetic-request-123',
    passwordProtected: protected,
  );
  test(
    'direct email contains exactly token, normalized recipient and retry identity',
    () async {
      await send();
      expect(requests.single, {
        'shareToken': 'synthetic-share-token-123',
        'recipientEmail': 'Recipient+Tag@example.test',
        'requestId': 'synthetic-request-123',
      });
      expect(
        newShareEmailRequestId(),
        matches(RegExp(r'^[A-Za-z0-9_-]{16,64}$')),
      );
    },
  );
  test('password-free links never reach the direct email callable', () async {
    await expectLater(
      send(protected: false),
      throwsA(isA<ShareEmailException>()),
    );
    expect(requests, isEmpty);
  });
  test(
    'mailbox normalization matches server bounds without changing local case',
    () {
      expect(
        normalizeShareRecipientEmail('  Recipient+tag@EXAMPLE.TEST  '),
        'Recipient+tag@example.test',
      );
      for (final address in [
        'a..b@example.test',
        '.a@example.test',
        'a.@example.test',
        '${'a' * 65}@example.test',
        'a@${'a' * 64}.test',
        'A <a@example.test>',
        'a@example.test,b@example.test',
        'a@example.test\r\nBcc:x@example.test',
        'a@-invalid.test',
        'a@invalid-.test',
      ]) {
        expect(
          isValidShareRecipientEmail(address),
          isFalse,
          reason: 'synthetic invalid mailbox',
        );
      }
    },
  );
  test('invalid recipient is rejected before any email request', () async {
    await expectLater(
      send(email: 'invalid address'),
      throwsA(isA<ShareEmailException>()),
    );
    expect(requests, isEmpty);
  });
  test(
    'account changes fail closed before and after an in-flight email request',
    () async {
      response = Completer<Map<String, dynamic>>();
      final inFlight = send();
      await Future<void>.delayed(Duration.zero);
      await auth.signOut();
      response!.complete({'accepted': true, 'status': 'accepted'});
      await expectLater(inFlight, throwsA(isA<ShareEmailException>()));
      await expectLater(send(), throwsA(isA<ShareEmailException>()));
      expect(requests, hasLength(1));
    },
  );
  test(
    'provider errors never leak response bodies or private exception text',
    () async {
      failure = FirebaseFunctionsException(
        code: 'unavailable',
        message: 'private@example.test key=private-secret',
      );
      try {
        await send();
        fail('expected rejection');
      } on ShareEmailException catch (error) {
        expect(error.message, contains('could not be confirmed'));
        expect(error.message, isNot(contains('private@')));
        expect(error.message, isNot(contains('private-secret')));
      }
      failure = null;
      await send();
      expect(requests.first, requests.last);
    },
  );
  test(
    'mail app handoff encodes the complete private link only in its local body',
    () {
      final link = Uri.parse(
        'https://share.example.test/share/synthetic-token#key=${'A' * 43}',
      );
      final mailto = shareLinkMailto(
        recipientEmail: 'Recipient+tag@EXAMPLE.TEST',
        completeLink: link,
      );
      expect(mailto.scheme, 'mailto');
      expect(mailto.path, 'Recipient+tag@example.test');
      expect(mailto.fragment, isEmpty);
      expect(mailto.queryParameters['body'], contains(link.toString()));
      expect(mailto.queryParameters.keys.toSet(), {'subject', 'body'});
      expect(requests, isEmpty);
    },
  );
  test(
    'local mail handoff allows guarded loopback HTTP and rejects remote HTTP',
    () {
      expect(
        shareLinkMailto(
          recipientEmail: 'a@example.test',
          completeLink: Uri.parse(
            'http://127.0.0.1:8080/share/token#key=${'A' * 43}',
          ),
        ).scheme,
        'mailto',
      );
      expect(
        () => shareLinkMailto(
          recipientEmail: 'a@example.test',
          completeLink: Uri.parse(
            'http://remote.example.test/share/token#key=${'A' * 43}',
          ),
        ),
        throwsA(isA<ShareEmailException>()),
      );
    },
  );
}
