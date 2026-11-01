class CheckoutPlanIntent {
  const CheckoutPlanIntent({required this.tier, required this.interval});

  final String tier;
  final String interval;
}

class CheckoutPlanIntentStore {
  CheckoutPlanIntentStore._();

  static final CheckoutPlanIntentStore instance = CheckoutPlanIntentStore._();

  CheckoutPlanIntent? _pending;

  CheckoutPlanIntent? get pending => _pending;

  void remember({required String tier, required String interval}) {
    final normalizedTier = tier.trim().toLowerCase();
    final normalizedInterval = interval.trim().toLowerCase();
    if (!const {'basic', 'pro', 'ultra'}.contains(normalizedTier) ||
        !const {'monthly', 'yearly'}.contains(normalizedInterval)) {
      return;
    }
    _pending = CheckoutPlanIntent(
      tier: normalizedTier,
      interval: normalizedInterval,
    );
  }

  CheckoutPlanIntent? take() {
    final value = _pending;
    _pending = null;
    return value;
  }

  void clear() {
    _pending = null;
  }
}
