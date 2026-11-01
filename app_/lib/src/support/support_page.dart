import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../shared/app_page_title.dart';

Future<void> _openSupportLink(
  BuildContext context,
  Uri uri, {
  required String fallback,
  LaunchMode mode = LaunchMode.platformDefault,
}) async {
  try {
    if (await launchUrl(uri, mode: mode)) {
      return;
    }
  } on Object {
    // Devices without an email or browser handler still get a recovery path.
  }
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(fallback)));
  }
}

class SupportPage extends StatelessWidget {
  const SupportPage({super.key});

  static const supportEmail = 'support@ronikcloud.com';
  static final Uri _supportEmailUri = Uri(
    scheme: 'mailto',
    path: supportEmail,
    queryParameters: const {'subject': 'RonikCloud support request'},
  );
  static final Uri _refundEmailUri = Uri(
    scheme: 'mailto',
    path: supportEmail,
    queryParameters: const {'subject': 'RonikCloud refund request'},
  );
  static final Uri _appleRefundUri = Uri.parse(
    'https://reportaproblem.apple.com/',
  );

  Future<void> _openSupportEmail(BuildContext context) => _openSupportLink(
    context,
    _supportEmailUri,
    fallback: 'Email support at support@ronikcloud.com.',
  );

  Future<void> _openRefundEmail(BuildContext context) => _openSupportLink(
    context,
    _refundEmailUri,
    fallback:
        'Email support@ronikcloud.com with the subject "RonikCloud refund request".',
  );

  Future<void> _openAppleRefund(BuildContext context) => _openSupportLink(
    context,
    _appleRefundUri,
    mode: LaunchMode.externalApplication,
    fallback: 'Open reportaproblem.apple.com for an Apple refund.',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('RonikCloud Support')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'How can we help?',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Contact RonikCloud support for account access, uploads, downloads, backups, billing, privacy requests, bug reports, or feature feedback.',
                        style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: () => _openSupportEmail(context),
                            icon: const Icon(Icons.email_outlined),
                            label: const Text('Email RonikCloud support'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _openRefundEmail(context),
                            icon: const Icon(Icons.receipt_long_outlined),
                            label: const Text('Stripe refund or billing help'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _openAppleRefund(context),
                            icon: const Icon(Icons.apple),
                            label: const Text('Request Apple refund'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const SelectableText(
                        supportEmail,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const _SupportCard(
                title: 'Include with your request',
                icon: Icons.checklist_outlined,
                items: [
                  'Your Support code from Data safety center > Privacy.',
                  'Your device platform and RonikCloud app version.',
                  'What you expected, what happened, and steps that reproduce the issue.',
                  'The approximate time of the problem and any non-sensitive error message.',
                ],
              ),
              const SizedBox(height: 12),
              const _SupportCard(
                title: 'Protect your account',
                icon: Icons.shield_outlined,
                body:
                    'Never email your password, encryption passphrase, authentication code, private key, payment-card number, or recovery material. RonikCloud support does not need these secrets to investigate a request.',
              ),
              const SizedBox(height: 12),
              const _SupportCard(
                title: 'Account and data controls',
                icon: Icons.manage_accounts_outlined,
                body:
                    'Canceling renewal, requesting account closure, and requesting a refund are separate actions. Settings > Account Security > Request account closure records an authenticated support request; it does not immediately sign you out, end access, cancel billing, or delete data. Cancel renewal separately if desired. We aim to acknowledge account requests within two Czech business days, while completion may take longer for verification or provider safety checks. Share your account email only when support must verify ownership for billing, account access, or a privacy request.',
              ),
              const SizedBox(height: 12),
              const _SupportCard(
                title: 'Payment-detail privacy',
                icon: Icons.credit_card_off_outlined,
                body:
                    'RonikCloud never receives or stores your full card number or card security code. Stripe or the applicable app store handles payment credentials. Auto-renewing plans require the provider to retain a reusable credential. Permanent account deletion requests removal of verified linked Stripe customer profiles; app-store payment details remain controlled by the store account.',
              ),
              const SizedBox(height: 12),
              _SupportLinks(colors: colors),
            ],
          ),
        ),
      ),
    ).withAppPageTitle('Support | RonikCloud');
  }
}

class _SupportCard extends StatelessWidget {
  const _SupportCard({
    required this.title,
    required this.icon,
    this.body,
    this.items = const [],
  });

  final String title;
  final IconData icon;
  final String? body;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            if (body != null) ...[
              const SizedBox(height: 12),
              Text(
                body!,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
              ),
            ],
            if (items.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Icon(Icons.circle, size: 6),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SupportLinks extends StatelessWidget {
  const _SupportLinks({required this.colors});

  final ColorScheme colors;

  Future<void> _open(BuildContext context, Uri uri) => _openSupportLink(
    context,
    uri,
    fallback:
        'Could not open this page. Open ${uri.host}${uri.path} in your browser.',
  );

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: () =>
                  _open(context, Uri.parse('https://ronikcloud.com/privacy')),
              child: const Text('Privacy Policy'),
            ),
            TextButton(
              onPressed: () =>
                  _open(context, Uri.parse('https://ronikcloud.com/terms')),
              child: const Text('Terms of Service'),
            ),
            TextButton(
              onPressed: () => _open(
                context,
                Uri.parse('https://ronikcloud.com/delete-account'),
              ),
              child: const Text('Request account closure'),
            ),
            TextButton(
              onPressed: () => _open(
                context,
                Uri.parse('https://ronikcloud.com/cancellation-refund'),
              ),
              child: const Text('Cancellation and refunds'),
            ),
            TextButton(
              onPressed: () =>
                  _open(context, Uri.parse('https://ronikcloud.com/legal')),
              child: const Text('All legal documents'),
            ),
          ],
        ),
      ),
    );
  }
}
