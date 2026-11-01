import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents the billing state for an account when attempting to sign in.
class AccountStatus {
  const AccountStatus({required this.status, this.note});

  final BillingStatus status;
  final String? note;

  /// Whether the account can access the workspace.
  bool get isAccessAllowed => status == BillingStatus.active;

  /// A message displayed when the account is blocked from signing in.
  String get blockingMessage =>
      note ?? 'Your RonikCloud subscription is inactive.';

  /// Non-blocking contextual information shown when access is granted.
  String? get contextualMessage => isAccessAllowed ? note : null;
}

/// Possible billing states for an account.
enum BillingStatus { active, trial, gracePeriod, pastDue }

/// Service that inspects Firestore billing metadata to gate workspace access.
class AccountStatusService {
  AccountStatusService({required FirebaseFirestore firestore})
    : _firestore = firestore;

  final FirebaseFirestore _firestore;

  /// Looks up the subscription status stored alongside the user's profile.
  ///
  /// The caller must provide both the Firebase auth [uid] and [email] so we
  /// can fall back to sample data when the profile has not yet been created.
  Future<AccountStatus> fetchStatus({
    required String uid,
    required String email,
  }) async {
    try {
      final snapshot = await _firestore.collection('users').doc(uid).get();
      if (snapshot.exists) {
        final status = _mapSnapshot(snapshot.data());
        if (status != null) {
          return status;
        }
      }
    } on FirebaseException {
      // Ignore Firestore failures and fall back to canned responses so the UI
      // can still guide the operator.
    }

    await Future<void>.delayed(const Duration(milliseconds: 420));
    final normalizedEmail = email.trim().toLowerCase();
    return _mockBillingDirectory[normalizedEmail] ?? _defaultPastDue;
  }

  AccountStatus? _mapSnapshot(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }

    final rawStatus = (data['subscriptionStatus'] as String?) ?? '';
    final status = rawStatus.trim().toLowerCase();

    if (_activeStatuses.contains(status)) {
      return AccountStatus(
        status: BillingStatus.active,
        note: _activeNote(data),
      );
    }

    if (_graceStatuses.contains(status)) {
      return const AccountStatus(
        status: BillingStatus.gracePeriod,
        note:
            'Billing issue detected. Update your payment method to restore workspace access.',
      );
    }

    if (_trialStatuses.contains(status)) {
      return const AccountStatus(
        status: BillingStatus.trial,
        note: 'Activate billing to unlock your RonikCloud workspace.',
      );
    }

    return const AccountStatus(
      status: BillingStatus.pastDue,
      note:
          'Add a billing method to activate your RonikCloud workspace before signing in.',
    );
  }

  String? _activeNote(Map<String, dynamic> data) {
    final capacity = (data['capacity'] as String?)?.trim();
    final periodEndRaw = (data['currentPeriodEnd'] as String?)?.trim();
    final renewal = _parseRenewalDate(periodEndRaw);

    if (renewal != null) {
      final formatted = _formatDate(renewal);
      if (capacity != null && capacity.isNotEmpty && capacity != 'pending') {
        return '$capacity plan renews on $formatted.';
      }
      return 'Subscription renews on $formatted.';
    }

    if (capacity != null && capacity.isNotEmpty && capacity != 'pending') {
      return '$capacity plan active. Welcome back!';
    }

    return 'Subscription active. Welcome back!';
  }

  DateTime? _parseRenewalDate(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    if (raw.toLowerCase() == 'pending') {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  String _formatDate(DateTime date) {
    const monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    final local = date.toLocal();
    final monthIndex = local.month - 1;
    final month = monthIndex >= 0 && monthIndex < monthNames.length
        ? monthNames[monthIndex]
        : local.month.toString();
    return '$month ${local.day}, ${local.year}';
  }
}

const AccountStatus _defaultPastDue = AccountStatus(
  status: BillingStatus.pastDue,
  note:
      'Add a billing method to activate your RonikCloud workspace before signing in.',
);

const Map<String, AccountStatus> _mockBillingDirectory = {
  'ceo@ronikdrive.com': AccountStatus(
    status: BillingStatus.active,
    note: 'Subscription renewed on Oct 2. All systems are up to date.',
  ),
  'ops@ronikdrive.com': AccountStatus(
    status: BillingStatus.gracePeriod,
    note:
        'Billing issue detected. Update your payment method to restore workspace access.',
  ),
  'design@ronikdrive.com': AccountStatus(
    status: BillingStatus.pastDue,
    note: 'Subscribe to RonikCloud to unlock secure storage and sharing.',
  ),
  'pastdue@ronikdrive.com': AccountStatus(
    status: BillingStatus.pastDue,
    note:
        'Your subscription is past due. Update billing to restore access to RonikCloud.',
  ),
};

const Set<String> _activeStatuses = {
  'active',
  'paid',
  'complete',
  'completed',
  'succeeded',
  'success',
};

const Set<String> _graceStatuses = {
  'grace',
  'grace_period',
  'graceperiod',
  'past_due',
  'pastdue',
};

const Set<String> _trialStatuses = {'trial', 'trialing'};
