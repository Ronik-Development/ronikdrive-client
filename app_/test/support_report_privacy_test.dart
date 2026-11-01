import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_storage/src/support/support_report_privacy.dart';

void main() {
  test(
    'support payload removes common identifiers before leaving the device',
    () {
      final payload = SupportReportPayload.prepare(
        title: 'report.pdf will not open',
        description:
            'Email private@example.com; path C:\\Users\\alice\\report.pdf; '
            'server /home/alice/customer-a/report.pdf; '
            'URL https://ronikcloud.com/share/private-token?key=secret; '
            'password=hunter2; Bearer secret-token',
        stepsToReproduce: 'Open report.pdf and retry.',
        platform: 'windows',
        buildMode: 'release',
      ).toCallablePayload();

      final serialized = payload.toString();
      for (final privateValue in <String>[
        'private@example.com',
        '\\alice\\',
        'report.pdf',
        'customer-a',
        'private-token',
        'key=secret',
        'hunter2',
        'secret-token',
      ]) {
        expect(serialized, isNot(contains(privateValue)));
      }
      expect(payload['privacyVersion'], supportReportPrivacyVersion);
      expect(payload, isNot(contains('uid')));
      expect(payload, isNot(contains('email')));
      expect(payload, isNot(contains('fileName')));
    },
  );

  test('support payload is bounded and validates platform metadata', () {
    expect(
      () => SupportReportPayload.prepare(
        title: '',
        description: '',
        stepsToReproduce: '',
        platform: 'web',
        buildMode: 'release',
      ),
      throwsA(isA<SupportReportPrivacyException>()),
    );
    expect(
      () => SupportReportPayload.prepare(
        title: '',
        description: 'x' * 4001,
        stepsToReproduce: '',
        platform: 'web',
        buildMode: 'release',
      ),
      throwsA(isA<SupportReportPrivacyException>()),
    );
    expect(
      () => SupportReportPayload.prepare(
        title: '',
        description: 'Problem',
        stepsToReproduce: '',
        platform: 'browser-from-client',
        buildMode: 'release',
      ),
      throwsA(isA<SupportReportPrivacyException>()),
    );
  });

  test('support receipt requires an opaque code and bounded retention', () {
    final receipt = SupportReportReceipt.fromCallableResult(<String, dynamic>{
      'accepted': true,
      'supportCode': 'ABC123-DEF456',
      'retentionDays': 90,
    });
    expect(receipt.supportCode, 'ABC123-DEF456');
    expect(receipt.retentionDays, 90);

    expect(
      () => SupportReportReceipt.fromCallableResult(<String, dynamic>{
        'accepted': true,
        'supportCode': 'firebase-user-123',
        'retentionDays': 90,
      }),
      throwsA(isA<SupportReportPrivacyException>()),
    );
    expect(
      () => SupportReportReceipt.fromCallableResult(<String, dynamic>{
        'supportCode': 'ABC123-DEF456',
        'retentionDays': 90,
      }),
      throwsA(isA<SupportReportPrivacyException>()),
    );
  });
}
