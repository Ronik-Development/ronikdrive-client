import 'package:cloud_storage/src/billing/checkout_plan_intent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(CheckoutPlanIntentStore.instance.clear);

  test('remembers and consumes a valid landing-page plan choice', () {
    CheckoutPlanIntentStore.instance.remember(
      tier: 'Basic',
      interval: 'yearly',
    );

    final intent = CheckoutPlanIntentStore.instance.take();

    expect(intent?.tier, 'basic');
    expect(intent?.interval, 'yearly');
    expect(CheckoutPlanIntentStore.instance.pending, isNull);
  });

  test('ignores unsupported plan values', () {
    CheckoutPlanIntentStore.instance.remember(
      tier: 'enterprise',
      interval: 'weekly',
    );

    expect(CheckoutPlanIntentStore.instance.pending, isNull);
  });
}
