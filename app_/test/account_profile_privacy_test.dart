import 'package:cloud_storage/src/privacy/account_profile_privacy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('protected account profile duplicates no Auth identity', () {
    final payload = protectedAccountProfileCreatePayload(
      createdAt: '2026-08-02T10:00:00.000Z',
      legalVersion: '2026-08-02',
      legalAcceptedAt: '2026-08-02T10:00:00.000Z',
      productUpdatesOptIn: false,
    );

    expect(payload['profilePrivacyVersion'], accountProfilePrivacyVersion);
    expect(payload.containsKey('email'), isFalse);
    expect(payload.containsKey('name'), isFalse);
    expect(payload.containsKey('displayName'), isFalse);
    expect(payload['productUpdatesOptIn'], isFalse);
    expect(payload.containsKey('productUpdatesOptInAt'), isFalse);
  });

  test('optional product consent retains only policy state and time', () {
    final payload = protectedAccountProfileCreatePayload(
      createdAt: '2026-08-02T10:00:00.000Z',
      legalVersion: '2026-08-02',
      legalAcceptedAt: '2026-08-02T10:00:00.000Z',
      productUpdatesOptIn: true,
    );

    expect(payload['productUpdatesOptIn'], isTrue);
    expect(payload['productUpdatesOptInAt'], '2026-08-02T10:00:00.000Z');
    expect(
      payload.keys.toSet().intersection(<String>{
        'email',
        'name',
        'displayName',
      }),
      isEmpty,
    );
  });
}
