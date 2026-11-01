import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const Key accountClosureDeleteNowKey = Key('account-closure-delete-now');
const Key accountClosureRequestKey = Key('account-closure-request');
const Key accountClosureManageAppleKey = Key('account-closure-manage-apple');
const Key accountClosureAppleRefundKey = Key('account-closure-apple-refund');
const Key accountClosureStripeRefundKey = Key('account-closure-stripe-refund');
const Key accountClosureManageGooglePlayKey = Key(
  'account-closure-manage-google-play',
);
const Key accountClosureGooglePlayRefundKey = Key(
  'account-closure-google-play-refund',
);
const Key accountClosureUnknownProviderHelpKey = Key(
  'account-closure-unknown-provider-help',
);

const bool selfServiceAccountDeletionEnabled = bool.fromEnvironment(
  'SELF_SERVICE_ACCOUNT_DELETION_ENABLED',
  defaultValue: false,
);

enum AccountClosureAction { cancel, requestClosure, deleteNow }

final Uri accountClosureAppleSubscriptionsUri = Uri.parse(
  'https://apps.apple.com/account/subscriptions',
);
final Uri accountClosureAppleRefundUri = Uri.parse(
  'https://reportaproblem.apple.com/',
);
final Uri accountClosureGooglePlaySubscriptionsUri = Uri.parse(
  'https://play.google.com/store/account/subscriptions',
);
final Uri accountClosureGooglePlayRefundUri = Uri.parse(
  'https://support.google.com/googleplay/answer/2479637',
);
final Uri accountClosureStripeRefundUri = Uri(
  scheme: 'mailto',
  path: 'support@ronikcloud.com',
  queryParameters: const {'subject': 'RonikCloud refund request'},
);
final Uri accountClosureUnknownProviderHelpUri = Uri(
  scheme: 'mailto',
  path: 'support@ronikcloud.com',
  queryParameters: const {'subject': 'RonikCloud billing provider help'},
);
final Uri accountClosureRequestSupportUri = Uri(
  scheme: 'mailto',
  path: 'support@ronikcloud.com',
  queryParameters: const {
    'subject': 'RonikCloud account closure request',
    'body':
        'I could not submit the in-app account closure request. Please help me request closure for the account associated with this email. I understand that my sign-in, access, data, and billing remain active until RonikCloud verifies the request, confirms the effects, and completes closure. I will not send a password, authentication code, encryption key, or payment-card details.',
  },
);

typedef AccountClosureLinkLauncher = Future<bool> Function(Uri uri);

class AccountClosureProfile {
  const AccountClosureProfile({
    required this.hasStripeBilling,
    required this.hasAppleBilling,
    required this.hasUnknownBillingProvider,
    required this.billingStateKnown,
    this.hasGooglePlayBilling = false,
    this.paidThrough,
  });

  factory AccountClosureProfile.fromProfile(Map<String, dynamic>? profile) {
    final data = profile ?? const <String, dynamic>{};
    final providers = <String>{};

    void addProvider(Object? value) {
      final normalized = value?.toString().trim().toLowerCase();
      if (normalized != null && normalized.isNotEmpty) {
        providers.add(normalized);
      }
    }

    addProvider(data['billingPrimaryProvider']);
    addProvider(data['subscriptionProvider']);
    final activeProviders = data['billingProvidersActive'];
    if (activeProviders is Iterable) {
      for (final provider in activeProviders) {
        addProvider(provider);
      }
    }
    final billingSources = data['billingSources'];
    if (billingSources is Map) {
      for (final provider in billingSources.keys) {
        addProvider(provider);
      }
    }

    final hasStripeCustomer =
        data['subscriptionCustomerId']?.toString().trim().isNotEmpty == true;
    final hasAppleAccountToken =
        data['appleAppAccountToken']?.toString().trim().isNotEmpty == true;
    const recognizedProviders = <String>{
      'stripe',
      'appstore',
      'app_store',
      'apple',
      'googleplay',
      'google_play',
      'play',
    };
    const nonBillingProviders = <String>{
      'reviewgrant',
      'review_grant',
      'disabled',
      'none',
      'free',
    };

    final paidThroughCandidates = <DateTime?>[
      _coerceDate(data['currentPeriodEnd'] ?? data['subscriptionEndDate']),
    ];
    if (billingSources is Map) {
      for (final source in billingSources.values) {
        if (source is Map) {
          paidThroughCandidates.add(
            _coerceDate(
              source['currentPeriodEnd'] ??
                  source['subscriptionEndDate'] ??
                  source['current_period_end'],
            ),
          );
        }
      }
    }
    final paidThrough = paidThroughCandidates
        .whereType<DateTime>()
        .fold<DateTime?>(
          null,
          (latest, candidate) =>
              latest == null || candidate.isAfter(latest) ? candidate : latest,
        );

    return AccountClosureProfile(
      hasStripeBilling: hasStripeCustomer || providers.contains('stripe'),
      hasAppleBilling:
          hasAppleAccountToken ||
          providers.contains('appstore') ||
          providers.contains('app_store') ||
          providers.contains('apple'),
      hasGooglePlayBilling:
          providers.contains('googleplay') ||
          providers.contains('google_play') ||
          providers.contains('play'),
      hasUnknownBillingProvider: providers.any(
        (provider) =>
            !recognizedProviders.contains(provider) &&
            !nonBillingProviders.contains(provider),
      ),
      billingStateKnown: profile != null,
      paidThrough: paidThrough,
    );
  }

  final bool hasStripeBilling;
  final bool hasAppleBilling;
  final bool hasGooglePlayBilling;
  final bool hasUnknownBillingProvider;
  final bool billingStateKnown;
  final DateTime? paidThrough;

  static DateTime? _coerceDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is num) {
      final milliseconds = value > 100000000000
          ? value.toInt()
          : (value * 1000).round();
      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        return DateTime.tryParse(trimmed);
      }
    }
    return null;
  }
}

Future<AccountClosureAction> showAccountClosureDialog({
  required BuildContext context,
  required Map<String, dynamic>? profileData,
  AccountClosureLinkLauncher? launchLink,
  bool selfServiceDeletionEnabled = selfServiceAccountDeletionEnabled,
}) async {
  final profile = AccountClosureProfile.fromProfile(profileData);
  final launcher = launchLink ?? _launchAccountClosureLink;
  final result = await showDialog<AccountClosureAction>(
    context: context,
    builder: (dialogContext) => _AccountClosureDialog(
      profile: profile,
      launchLink: launcher,
      selfServiceDeletionEnabled: selfServiceDeletionEnabled,
    ),
  );
  return result ?? AccountClosureAction.cancel;
}

Future<bool> _launchAccountClosureLink(Uri uri) {
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> showAccountClosureRequestRecordedDialog({
  required BuildContext context,
  required bool alreadyRequested,
  required String status,
  Uri? receiptUrl,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        alreadyRequested
            ? 'Closure request already recorded'
            : 'Closure request recorded',
      ),
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Queue status: $status. Your request authorizes permanent deletion. Account access and billing may remain active until processing begins. Cancel renewal separately to stop a future charge. We aim to acknowledge requests within two Czech business days and respond within one month. If an extension is permitted, we will explain it within that first month.',
          ),
          if (receiptUrl != null) ...[
            const SizedBox(height: 16),
            const Text(
              'Save this private status link before your account closes. It works without signing in. Anyone with the link can see the request status. A new request receipt replaces the previous link.',
            ),
            const SizedBox(height: 8),
            SelectableText(receiptUrl.toString()),
          ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Understood'),
        ),
      ],
    ),
  );
}

Future<void> showAccountClosureRequestFallbackDialog({
  required BuildContext context,
  required String message,
  AccountClosureLinkLauncher? launchLink,
}) {
  final launcher = launchLink ?? _launchAccountClosureLink;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Closure request not recorded'),
      content: Text(
        '$message No account, access, data, or billing change was made. Try the in-app request again, or email support from the address associated with your account. Never send a password, authentication code, encryption key, or payment-card details.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Go back'),
        ),
        FilledButton.icon(
          onPressed: () async {
            final opened = await launcher(accountClosureRequestSupportUri);
            if (!dialogContext.mounted) {
              return;
            }
            if (opened) {
              Navigator.of(dialogContext).pop();
              return;
            }
            ScaffoldMessenger.maybeOf(dialogContext)?.showSnackBar(
              const SnackBar(
                content: Text('Email support at support@ronikcloud.com.'),
              ),
            );
          },
          icon: const Icon(Icons.email_outlined),
          label: const Text('Email support'),
        ),
      ],
    ),
  );
}

class _AccountClosureDialog extends StatelessWidget {
  const _AccountClosureDialog({
    required this.profile,
    required this.launchLink,
    required this.selfServiceDeletionEnabled,
  });

  final AccountClosureProfile profile;
  final AccountClosureLinkLauncher launchLink;
  final bool selfServiceDeletionEnabled;

  Future<void> _open(BuildContext context, Uri uri) async {
    final opened = await launchLink(uri);
    if (!opened && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('The billing page could not be opened. Try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final paidThrough = _formatDate(profile.paidThrough);
    return AlertDialog(
      title: Text(
        selfServiceDeletionEnabled
            ? 'Before deleting your account'
            : 'Request account closure',
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!selfServiceDeletionEnabled) ...[
                const _ClosureSection(
                  icon: Icons.support_agent_outlined,
                  title: 'Permanent account closure',
                  body:
                      'Submitting this authenticated request authorizes permanent deletion of your account and personal files. Download anything you need first. Deletion runs in stages: account access is disabled before files are erased, and verified linked Stripe subscriptions are canceled during closure. You do not need to send a separate email to confirm. We target completion within 28 days and respond within one month; if a lawful extension is needed, we explain it within that first month. Save the private status receipt. Cancel renewal separately to avoid a charge while the request is queued.',
                ),
                const SizedBox(height: 16),
              ],
              const _ClosureSection(
                icon: Icons.autorenew_outlined,
                title: 'Cancel renewal',
                body:
                    'Canceling renewal is different from deleting your account. '
                    'It stops a future renewal while your account and files remain available for the applicable paid and retention periods.',
              ),
              if (paidThrough != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'The current paid period is shown as ending on $paidThrough if you only cancel renewal. '
                    '${selfServiceDeletionEnabled ? 'Deleting the account ends access immediately' : 'Access ends when closure processing disables the account'}; unused paid time is not automatically refunded.',
                  ),
                ),
              if (profile.hasStripeBilling || !profile.billingStateKnown) ...[
                const SizedBox(height: 16),
                _ClosureSection(
                  icon: Icons.credit_card_off_outlined,
                  title: 'Stripe billing',
                  body: selfServiceDeletionEnabled
                      ? profile.billingStateKnown
                            ? 'Deleting the account immediately ends the linked Stripe subscription and paid access without an automatic refund. It requests removal of the Stripe customer and reusable payment details. RonikCloud does not keep full card numbers. Stripe may retain transaction, invoice, fraud-prevention, or legally required records.'
                            : 'Billing status could not be refreshed. If this account uses Stripe, deleting it immediately ends the Stripe subscription and paid access without an automatic refund, and requests removal of verified linked Stripe customer profiles and reusable payment details.'
                      : profile.billingStateKnown
                      ? 'While a closure request is pending, the linked Stripe subscription and paid access remain active. Closure processing cancels verified linked Stripe subscriptions. A completed closure requests removal of the Stripe customer and reusable payment details without automatically issuing a refund. RonikCloud does not keep full card numbers; Stripe may retain transaction, invoice, fraud-prevention, or legally required records.'
                      : 'Billing status could not be refreshed. Billing and access remain active while a closure request is pending. Closure processing identifies and cancels verified linked Stripe subscriptions; provider-held transaction records may remain.',
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: accountClosureStripeRefundKey,
                  onPressed: () =>
                      _open(context, accountClosureStripeRefundUri),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Stripe refund or billing help'),
                ),
              ],
              if (profile.hasAppleBilling || !profile.billingStateKnown) ...[
                const SizedBox(height: 16),
                _ClosureSection(
                  icon: Icons.apple,
                  title: 'Apple subscription',
                  body: selfServiceDeletionEnabled
                      ? profile.billingStateKnown
                            ? 'Deleting your RonikCloud account does not cancel an App Store subscription. It may continue and renew until you cancel it with Apple.'
                            : 'Billing status could not be refreshed. If you purchased through Apple, account deletion does not cancel that App Store subscription; cancel it with Apple to stop renewal.'
                      : profile.billingStateKnown
                      ? 'An App Store subscription remains active while the closure request is pending, and closing RonikCloud does not cancel it. Cancel it with Apple separately to stop renewal.'
                      : 'Billing status could not be refreshed. If you purchased through Apple, that subscription remains active while the closure request is pending and must be canceled with Apple separately.',
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: accountClosureManageAppleKey,
                      onPressed: () =>
                          _open(context, accountClosureAppleSubscriptionsUri),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Manage Apple'),
                    ),
                    OutlinedButton.icon(
                      key: accountClosureAppleRefundKey,
                      onPressed: () =>
                          _open(context, accountClosureAppleRefundUri),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('Apple refund'),
                    ),
                  ],
                ),
              ],
              if (profile.hasGooglePlayBilling ||
                  !profile.billingStateKnown) ...[
                const SizedBox(height: 16),
                _ClosureSection(
                  icon: Icons.shop_outlined,
                  title: 'Google Play subscription',
                  body: !profile.billingStateKnown
                      ? 'Billing status could not be refreshed. If you purchased through Google Play, cancel renewal in Google Play separately. Requesting or completing account closure does not cancel that subscription or automatically issue a refund.'
                      : selfServiceDeletionEnabled
                      ? 'Deleting your RonikCloud account does not cancel a Google Play subscription. It can continue renewing until you cancel renewal in Google Play. Deletion does not request or issue a refund.'
                      : 'A Google Play subscription that is still active can keep renewing while your closure request is pending and after your RonikCloud account closes. Closing RonikCloud does not cancel its renewal. Cancel renewal in Google Play separately; closure does not request or issue a refund.',
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: accountClosureManageGooglePlayKey,
                      onPressed: () => _open(
                        context,
                        accountClosureGooglePlaySubscriptionsUri,
                      ),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Manage Google Play'),
                    ),
                    OutlinedButton.icon(
                      key: accountClosureGooglePlayRefundKey,
                      onPressed: () =>
                          _open(context, accountClosureGooglePlayRefundUri),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('Google Play refund help'),
                    ),
                  ],
                ),
              ],
              if (profile.hasUnknownBillingProvider) ...[
                const SizedBox(height: 16),
                _ClosureSection(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Original billing provider',
                  body: selfServiceDeletionEnabled
                      ? 'A billing source linked to this account is not recognized by this app version. Deleting RonikCloud may not cancel its renewal or remove payment details held by that provider. Before deleting, cancel renewal and request any refund through the original purchase channel, or contact support if you cannot identify it.'
                      : 'A billing source linked to this account is not recognized by this app version. It remains active while the closure request is pending, and completing RonikCloud closure may not cancel its renewal or remove payment details held by that provider. Cancel renewal and request any refund through the original purchase channel, or contact support if you cannot identify it.',
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: accountClosureUnknownProviderHelpKey,
                  onPressed: () =>
                      _open(context, accountClosureUnknownProviderHelpUri),
                  icon: const Icon(Icons.support_agent_outlined),
                  label: const Text('Billing-provider help'),
                ),
              ],
              const SizedBox(height: 16),
              _ClosureSection(
                icon: Icons.currency_exchange_outlined,
                title: 'Refunds',
                body: selfServiceDeletionEnabled
                    ? 'Deleting the account does not automatically request or issue a refund. Request any refund through the original billing provider; eligibility is handled under the refund policy and any mandatory consumer rights.'
                    : 'Submitting or completing an account closure request does not automatically request or issue a refund. Request any refund through the original billing provider; eligibility is handled under the refund policy and any mandatory consumer rights.',
              ),
              const SizedBox(height: 16),
              _ClosureSection(
                icon: Icons.delete_forever_outlined,
                title: selfServiceDeletionEnabled
                    ? 'Permanent deletion'
                    : 'Closure effects',
                body: selfServiceDeletionEnabled
                    ? 'Deleting now permanently removes your RonikCloud account, personal files, and app data. Organization-owned workspace data may remain with that organization after your membership is removed. If you own a company workspace, ownership must be transferred or that workspace closed first; contact support if those controls are unavailable. This cannot be undone. Download anything you need first.'
                    : 'Completing your authenticated closure request permanently removes your RonikCloud account, personal files, and app data. Organization-owned workspace data may remain with that organization after membership is removed. A company owner cannot be closed until ownership is transferred or the workspace is closed; support will explain the available next step. Completed closure cannot be undone, so download anything you need first.',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(AccountClosureAction.cancel),
          child: const Text('Go back'),
        ),
        FilledButton.icon(
          key: selfServiceDeletionEnabled
              ? accountClosureDeleteNowKey
              : accountClosureRequestKey,
          style: selfServiceDeletionEnabled
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.of(context).pop(
            selfServiceDeletionEnabled
                ? AccountClosureAction.deleteNow
                : AccountClosureAction.requestClosure,
          ),
          icon: Icon(
            selfServiceDeletionEnabled
                ? Icons.delete_forever_outlined
                : Icons.outbox_outlined,
          ),
          label: Text(
            selfServiceDeletionEnabled
                ? 'Delete now'
                : 'Submit closure request',
          ),
        ),
      ],
    );
  }

  String? _formatDate(DateTime? value) {
    if (value == null) {
      return null;
    }
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }
}

class _ClosureSection extends StatelessWidget {
  const _ClosureSection({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(body),
            ],
          ),
        ),
      ],
    );
  }
}
