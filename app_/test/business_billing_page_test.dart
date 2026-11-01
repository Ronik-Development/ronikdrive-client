import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_storage/app_theme.dart';
import 'package:cloud_storage/src/business/business_billing_page.dart';
import 'package:cloud_storage/src/business/business_operations_service.dart';
import 'package:cloud_storage/src/business/business_storage_billing_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void billingTest(String description, WidgetTesterCallback callback) {
  testWidgets(
    description,
    callback,
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

Map<String, dynamic> sampleState({String status = 'not_configured'}) => {
  'isOwner': true,
  'status': status,
  'offer': {
    'offerHash': 'a' * 64,
    'costScheduleReference': 'synthetic-v1',
    'costScheduleText':
        'Synthetic fixture: documented storage, transfer and support costs are allocated to this company under the accepted schedule.',
    'capacityBytesPerMember': 1073741824,
    'collectionTerms':
        'Authorize monthly automatic payment in arrears. Each UTC service month has a USD 6 minimum total, including a partial first or final month. Above it the service subtotal is approved cost divided by 0.50. Taxes are separate. Cancel before the next month to stop future service; accrued charges remain due.',
  },
  'invoices': [
    {
      'period': '2026-09',
      'status': 'payment_action_required',
      'serviceSubtotalCents': 2000,
      'totalCents': 2400,
      'costUsdMicros': 10000000,
      'url': 'https://invoice.stripe.com/i/synthetic',
    },
  ],
};

void viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

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
  billingTest(
    'card setup requires separate agreement and automatic-charge consent and retries one identity',
    (tester) async {
      viewport(tester, const Size(1200, 1800));
      final attempts = <Map<String, Object?>>[];
      final urls = <Uri>[];
      final service = BusinessOperationsService(
        callable: (name, data) async {
          if (name == 'getBusinessBillingState') return sampleState();
          if (name == 'createBusinessBillingSetup') {
            attempts.add(Map.of(data));
            if (attempts.length == 1) throw const BusinessOperationsException();
            return {'url': 'https://checkout.stripe.com/c/synthetic'};
          }
          throw StateError('Unexpected synthetic callable');
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: BusinessBillingPage(
            service: service,
            openUrl: (url) async {
              urls.add(url);
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.widgetWithText(
        FilledButton,
        'Set up automatic billing with Stripe',
      );
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.tap(find.byType(CheckboxListTile).at(0));
      await tester.pump();
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.tap(find.byType(CheckboxListTile).at(1));
      await tester.pump();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(attempts, hasLength(1));
      expect(urls, isEmpty);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(attempts, hasLength(2));
      expect(attempts[0]['requestId'], attempts[1]['requestId']);
      expect(attempts[0]['offerHash'], 'a' * 64);
      expect(attempts[0]['authorizeAutomaticCharges'], true);
      expect(urls.single.host, 'checkout.stripe.com');
    },
  );
  billingTest(
    'pending setup resumes the server request instead of creating a fresh authorization',
    (tester) async {
      viewport(tester, const Size(1200, 1800));
      Map<String, Object?>? submission;
      final service = BusinessOperationsService(
        callable: (name, data) async {
          if (name == 'getBusinessBillingState') {
            return {
              ...sampleState(status: 'pending_setup'),
              'setupRequestId': 'b' * 32,
            };
          }
          submission = data;
          return {'url': 'https://checkout.stripe.com/c/synthetic'};
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: BusinessBillingPage(
            service: service,
            openUrl: (_) async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var index = 0; index < 2; index++) {
        await tester.tap(find.byType(CheckboxListTile).at(index));
        await tester.pump();
      }
      await tester.tap(find.text('Continue secure payment setup'));
      await tester.pumpAndSettle();
      expect(submission?['requestId'], 'b' * 32);
    },
  );
  billingTest('cancellation requires an explicit month-end confirmation', (
    tester,
  ) async {
    viewport(tester, const Size(1200, 1800));
    var cancellations = 0;
    final service = BusinessOperationsService(
      callable: (name, data) async {
        if (name == 'getBusinessBillingState') {
          return sampleState(status: 'active');
        }
        if (name == 'cancelBusinessAutomaticBilling') {
          cancellations++;
          return {};
        }
        throw StateError('Unexpected synthetic callable');
      },
    );
    await tester.pumpWidget(
      MaterialApp(home: BusinessBillingPage(service: service)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel future Business service'));
    await tester.pumpAndSettle();
    expect(cancellations, 0);
    await tester.tap(find.text('Keep service'));
    await tester.pumpAndSettle();
    expect(cancellations, 0);
    await tester.tap(find.text('Cancel future Business service'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel at month end'));
    await tester.pumpAndSettle();
    expect(cancellations, 1);
  });
  billingTest('background access refresh keeps the live workspace mounted', (
    tester,
  ) async {
    var mounts = 0;
    final service = BusinessOperationsService(
      callable: (_, _) async => {'accessActive': true},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BusinessStorageBillingGate(
          service: service,
          allowExternalPayments: true,
          child: _MountProbe(onMount: () => mounts++),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(mounts, 1);
    await tester.pump(const Duration(minutes: 5));
    await tester.pumpAndSettle();
    expect(mounts, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final settings in [
    (1280.0, 900.0, 1.0, false),
    (390.0, 844.0, 1.0, false),
    (320.0, 640.0, 2.0, false),
    (1280.0, 900.0, 1.0, true),
  ]) {
    final (width, height, scale, dark) = settings;
    billingTest('billing is readable at $width scale $scale dark $dark', (
      tester,
    ) async {
      viewport(tester, Size(width, height));
      final key = GlobalKey();
      final service = BusinessOperationsService(
        callable: (_, _) async => sampleState(),
      );
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
            child: BusinessBillingPage(service: service),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_BUSINESS_PREVIEWS')) {
        await _capture(
          tester,
          key,
          'billing-${width.toInt()}-${scale.toInt()}-${dark ? 'dark' : 'light'}-top',
        );
      }
      await scrollTo(tester, find.text('Set up automatic billing with Stripe'));
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_BUSINESS_PREVIEWS')) {
        await _capture(
          tester,
          key,
          'billing-${width.toInt()}-${scale.toInt()}-${dark ? 'dark' : 'light'}-consent',
        );
      }
    });
  }
}

class _MountProbe extends StatefulWidget {
  const _MountProbe({required this.onMount});
  final VoidCallback onMount;
  @override
  State<_MountProbe> createState() => _MountProbeState();
}

class _MountProbeState extends State<_MountProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const Text('Synthetic live workspace');
}

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
