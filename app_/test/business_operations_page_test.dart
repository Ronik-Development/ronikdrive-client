import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_storage/app_theme.dart';
import 'package:cloud_storage/src/business/business_operations_page.dart';
import 'package:cloud_storage/src/business/business_operations_service.dart';
import 'package:cloud_storage/src/business/business_service_agreement_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('Source Sans 3');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/SourceSans3-$weight.ttf'));
    }
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets(
    'ticket text is reviewed and filtered before transmission; uncertain retry reuses identity',
    (tester) async {
      _desktop(tester);
      final submissions = <Map<String, Object?>>[];
      final service = _service((name, data) async {
        if (name != 'createBusinessSupportTicket') return null;
        submissions.add(Map.of(data));
        if (submissions.length == 1) {
          throw StateError('synthetic-provider-secret');
        }
        return {
          'id': 'receipt',
          'kind': 'support',
          'priority': 'normal',
          'status': 'open',
          'description': data['description'],
          'firstResponseDueAt': '2026-10-20T08:00:00Z',
        };
      });
      await tester.pumpWidget(
        MaterialApp(home: BusinessOperationsPage(service: service)),
      );
      await tester.pumpAndSettle();
      final description = find.widgetWithText(
        TextField,
        'Describe the problem',
      );
      await tester.enterText(
        description,
        'Cannot upload. password=do-not-send',
      );
      final consent = find.byType(CheckboxListTile);
      await tester.ensureVisible(consent);
      await tester.tap(consent);
      await tester.pump();
      final submit = find.text('Submit support ticket');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.text('Review support ticket'), findsOneWidget);
      expect(submissions, isEmpty);
      await tester.tap(find.text('Send ticket'));
      await tester.pumpAndSettle();
      expect(submissions, hasLength(1));
      expect(submissions.first['description'], isNot(contains('do-not-send')));
      expect(find.textContaining('synthetic-provider-secret'), findsNothing);
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send ticket'));
      await tester.pumpAndSettle();
      expect(submissions[0]['requestId'], submissions[1]['requestId']);
      expect(find.textContaining('First-response deadline:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'restore requires confirmation and selected-file verification before recording a device report',
    (tester) async {
      _desktop(tester);
      final calls = <String>[];
      final verifiedFiles = <String>[];
      var verificationSucceeds = false;
      final service = _service((name, data) async {
        calls.add(name);
        if (name == 'restoreBusinessRecoveryFile') {
          return {
            'status': 'restored',
            'fileId': 'synthetic-file',
            'operationId': 'operation',
          };
        }
        if (name == 'recordBusinessRecoveryCheck') {
          return {'verification': 'customer_device_reported_verified'};
        }
        return null;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: BusinessOperationsPage(
            service: service,
            resolveFileName: (_) async => 'Quarterly report.pdf',
            verifyFile: (id) async {
              verifiedFiles.add(id);
              return verificationSucceeds;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('File recovery'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reveal name on this device'));
      await tester.pumpAndSettle();
      expect(find.text('Quarterly report.pdf'), findsOneWidget);
      final restore = find.byTooltip('Restore encrypted file');
      await tester.ensureVisible(restore);
      await tester.tap(restore);
      await tester.pumpAndSettle();
      expect(calls, isNot(contains('restoreBusinessRecoveryFile')));
      await tester.tap(find.text('Restore file'));
      await tester.pumpAndSettle();
      final verify = find.text('Verify restored file');
      await tester.scrollUntilVisible(
        verify,
        150,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(verify);
      await tester.pumpAndSettle();
      expect(verifiedFiles, ['synthetic-file']);
      expect(calls, isNot(contains('recordBusinessRecoveryCheck')));
      verificationSucceeds = true;
      await tester.ensureVisible(verify);
      await tester.tap(verify);
      await tester.pumpAndSettle();
      expect(calls, contains('recordBusinessRecoveryCheck'));
      expect(
        find.text('Customer device reported a verified read.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'service agreement requires both consent and authority and sends the server version hash',
    (tester) async {
      _desktop(tester);
      Map<String, Object?>? acceptance;
      final service = _service((name, data) async {
        if (name == 'getBusinessServiceTerms') {
          return {
            'version': 'synthetic-v1',
            'termsHash': 'a' * 64,
            'clauses': [
              'Synthetic Business service agreement. Pricing is a USD 6 minimum, with a 50% gross margin above it.',
            ],
          };
        }
        if (name == 'acceptBusinessServiceAgreement') {
          acceptance = data;
          return {'accepted': true, 'termsHash': 'a' * 64};
        }
        return null;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<bool>(
                    builder: (_) =>
                        BusinessServiceAgreementPage(service: service),
                  ),
                ),
                child: const Text('Open agreement'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open agreement'));
      await tester.pumpAndSettle();
      final action = find.widgetWithText(
        FilledButton,
        'Accept Business service agreement',
      );
      expect(tester.widget<FilledButton>(action).onPressed, isNull);
      final checks = find.byType(CheckboxListTile);
      for (final check in [checks.at(0), checks.at(1)]) {
        await tester.ensureVisible(check);
        await tester.tap(check);
        await tester.pump();
      }
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(acceptance, {
        'termsHash': 'a' * 64,
        'accepted': true,
        'authorizedRepresentative': true,
      });
      expect(find.text('Open agreement'), findsOneWidget);
    },
  );

  for (final (width, height, scale, dark) in [
    (1280.0, 900.0, 1.0, false),
    (390.0, 844.0, 1.0, false),
    (320.0, 640.0, 2.0, false),
    (1280.0, 900.0, 1.0, true),
  ]) {
    testWidgets('operations are readable at $width scale $scale dark $dark', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: RepaintBoundary(
            key: key,
            child: BusinessOperationsPage(service: _service()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in ['Support', 'File recovery', 'Service terms']) {
        final tab = find.widgetWithText(Tab, label);
        await tester.ensureVisible(tab);
        await tester.tap(tab);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('CAPTURE_BUSINESS_PREVIEWS')) {
          await _capture(
            tester,
            key,
            'operations-${width.toInt()}-${scale.toInt()}-${dark ? 'dark' : 'light'}-${label.split(' ').first}',
          );
        }
      }
    });
  }
}

void _desktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

BusinessOperationsService _service([
  Future<Map<String, dynamic>?> Function(
    String name,
    Map<String, Object?> data,
  )?
  override,
]) => BusinessOperationsService(
  callable: (name, data) async {
    final result = await override?.call(name, data);
    if (result != null) return result;
    return switch (name) {
      'getBusinessOperationsState' => {
        'guaranteeActive': false,
        'firstHumanResponseHours': 8,
      },
      'listBusinessSupportTickets' => {'tickets': <Object?>[]},
      'listBusinessRecoveryFiles' => {
        'files': [
          {
            'id': 'synthetic-file',
            'state': 'trashed',
            'revision': 'b' * 64,
            'bytes': 1048576,
            'storageScope': 'company_shared',
            'changedAt': '2026-10-19T09:00:00Z',
          },
        ],
      },
      'listBusinessRecoveryOperations' => {'operations': <Object?>[]},
      _ => throw StateError('Unexpected synthetic operation'),
    };
  },
);

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final dir = Directory('../.audit/business-previews');
    await dir.create(recursive: true);
    await File(
      '${dir.path}/$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
  });
}
