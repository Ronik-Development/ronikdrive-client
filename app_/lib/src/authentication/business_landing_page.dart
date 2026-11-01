import 'package:flutter/material.dart';

import '../shared/app_page_title.dart';
import '../business/business_demo_page.dart';
import 'account_environment.dart';

typedef BusinessAccountOpener =
    Future<void> Function(AccountEnvironment environment, bool register);

/// Public product information. Cloud services are needed only after a visitor
/// chooses to create an account or sign in.
class BusinessLandingPage extends StatefulWidget {
  const BusinessLandingPage({super.key, required this.openAccount});

  final BusinessAccountOpener openAccount;

  @override
  State<BusinessLandingPage> createState() => _BusinessLandingPageState();
}

class _BusinessLandingPageState extends State<BusinessLandingPage> {
  bool _openingAccount = false;
  bool _accountOpenFailed = false;

  Future<void> _openAccount(
    AccountEnvironment environment,
    bool register,
  ) async {
    if (_openingAccount) return;
    setState(() {
      _openingAccount = true;
      _accountOpenFailed = false;
    });
    try {
      await widget.openAccount(environment, register);
    } catch (_) {
      if (mounted) setState(() => _accountOpenFailed = true);
    } finally {
      if (mounted) setState(() => _openingAccount = false);
    }
  }

  void _goHome() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushNamedAndRemoveUntil('/', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        leadingWidth: 64,
        leading: IconButton(
          tooltip: 'RonikCloud home',
          onPressed: _goHome,
          icon: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png',
              width: 32,
              height: 32,
              excludeFromSemantics: true,
            ),
          ),
        ),
        title: const Text('Business'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          return SelectionArea(
            child: SingleChildScrollView(
              key: const ValueKey('business-page-scroll'),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 20 : 40,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            0,
                            compact ? 40 : 72,
                            0,
                            40,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 780),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Semantics(
                                  header: true,
                                  child: Text(
                                    'Your company’s files.\nA shared workspace.',
                                    style:
                                        (compact
                                                ? textScale > 1.3
                                                      ? theme
                                                            .textTheme
                                                            .headlineMedium
                                                      : theme
                                                            .textTheme
                                                            .displaySmall
                                                : theme.textTheme.displayMedium)
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              height: 1.12,
                                            ),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  'Choose Business when files belong to a company and people need different access. Keep a Personal workspace for the files you manage yourself.',
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    height: 1.6,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                OutlinedButton.icon(
                                  key: const ValueKey('business-explore-demo'),
                                  onPressed: _openingAccount
                                      ? null
                                      : () => Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (demoContext) =>
                                                BusinessDemoPage(
                                                  onCreateAccount: () {
                                                    Navigator.of(
                                                      demoContext,
                                                    ).pop();
                                                    _openAccount(
                                                      AccountEnvironment
                                                          .business,
                                                      true,
                                                    );
                                                  },
                                                ),
                                          ),
                                        ),
                                  icon: const Icon(
                                    Icons.space_dashboard_outlined,
                                  ),
                                  label: const Text(
                                    'Explore a sample workspace',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Semantics(
                          header: true,
                          child: Text(
                            'Which workspace fits your work?',
                            style: theme.textTheme.headlineSmall,
                          ),
                        ),
                        const SizedBox(height: 24),
                        LayoutBuilder(
                          builder: (context, choiceConstraints) {
                            final sideBySide =
                                choiceConstraints.maxWidth >= 760 * textScale;
                            final choices = [
                              _WorkspaceChoice(
                                title: 'Personal',
                                summary:
                                    'For your own files, independent work, and sharing with others.',
                                plan: 'Start with 1 GB free',
                                features: const [
                                  'A workspace you manage yourself',
                                  'Protected share links and file requests',
                                  'Larger paid storage plans when you need them',
                                ],
                                action: OutlinedButton(
                                  key: const ValueKey(
                                    'business-choose-personal',
                                  ),
                                  onPressed: _openingAccount
                                      ? null
                                      : () => _openAccount(
                                          AccountEnvironment.personal,
                                          true,
                                        ),
                                  child: const Text(
                                    'Create a Personal workspace',
                                  ),
                                ),
                              ),
                              _WorkspaceChoice(
                                title: 'Business',
                                summary:
                                    'For company files, shared spaces, and managing a team’s access.',
                                plan: 'USD 6 monthly minimum, before tax',
                                features: const [
                                  'A company workspace with member administration',
                                  'Groups and permissions for shared files',
                                  'Company billing follows your accepted cost schedule',
                                ],
                                action: FilledButton(
                                  key: const ValueKey(
                                    'business-create-account',
                                  ),
                                  onPressed: _openingAccount
                                      ? null
                                      : () => _openAccount(
                                          AccountEnvironment.business,
                                          true,
                                        ),
                                  child: const Text(
                                    'Create a Business account',
                                  ),
                                ),
                              ),
                            ];
                            if (!sideBySide) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  choices[0],
                                  const Divider(height: 56),
                                  choices[1],
                                ],
                              );
                            }
                            return IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(child: choices[0]),
                                  const VerticalDivider(width: 64),
                                  Expanded(child: choices[1]),
                                ],
                              ),
                            );
                          },
                        ),
                        if (_openingAccount) ...[
                          const SizedBox(height: 16),
                          const Text('Opening your account setup…'),
                        ],
                        if (_accountOpenFailed) ...[
                          const SizedBox(height: 16),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              'Account setup could not be opened. Check your connection and try again.',
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Text(
                          'Review your company’s cost schedule, storage capacity and automatic payment authorization before activating billing. A separate Personal subscription is not required for company-sponsored storage. Sharing a few files does not require a Business account.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton.icon(
                          key: const ValueKey('business-sign-in'),
                          onPressed: _openingAccount
                              ? null
                              : () => _openAccount(
                                  AccountEnvironment.business,
                                  false,
                                ),
                          icon: const Icon(Icons.login),
                          label: const Text('Business sign in'),
                        ),
                        const SizedBox(height: 56),
                        const Divider(height: 1),
                        const _BusinessDetail(
                          title: 'Keep company work together',
                          body:
                              'Use company and group spaces for shared files. Company membership and administrative roles keep access separate from a personal file collection.',
                        ),
                        const Divider(height: 1),
                        const _BusinessDetail(
                          title: 'Give people the access they need',
                          body:
                              'Manage members, organize groups, and control file permissions. Shared spaces check current membership and allowed actions rather than giving everyone the same access.',
                        ),
                        const Divider(height: 1),
                        const _BusinessDetail(
                          title: 'Protect files before upload',
                          body:
                              'RonikCloud encrypts files on your device before uploading them. Set up encryption and keep recovery information safe so your authorized team can continue working with protected files.',
                        ),
                        const Divider(height: 1),
                        const _BusinessDetail(
                          title: 'Business service agreements',
                          body:
                              'Contracted Business services have a minimum total monthly charge of USD 6. Above that minimum, total pricing is documented attributable service cost divided by 0.50, targeting a 50% gross margin. Review the service agreement and cost schedule before acceptance; applicable taxes are separate. Contracted 24/7 support has an eight-hour human first-response deadline once coverage is activated. Missed contracted deadlines open provider compensation reviews. Explore the sample workspace to see support and file recovery workflows. Weekly automated adversarial checks use synthetic fixtures; they are not independent human red-team assessments.',
                        ),
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              TextButton.icon(
                                onPressed: () =>
                                    Navigator.of(context).pushNamed('/support'),
                                icon: const Icon(Icons.help_outline),
                                label: const Text('Contact support'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pushNamed('/privacy'),
                                child: const Text('Privacy and data ownership'),
                              ),
                              TextButton(
                                onPressed: _goHome,
                                child: const Text('Back to RonikCloud'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ).withAppPageTitle('RonikCloud for Business | Choose Your Workspace');
  }
}

class _WorkspaceChoice extends StatelessWidget {
  const _WorkspaceChoice({
    required this.title,
    required this.summary,
    required this.plan,
    required this.features,
    required this.action,
  });

  final String title;
  final String summary;
  final String plan;
  final List<String> features;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: theme.textTheme.headlineMedium),
        ),
        const SizedBox(height: 12),
        Text(summary, style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
        const SizedBox(height: 20),
        Text(
          plan,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 20),
        for (final feature in features)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              feature,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
        const SizedBox(height: 12),
        action,
      ],
    );
  }
}

class _BusinessDetail extends StatelessWidget {
  const _BusinessDetail({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Text(
            body,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
          ),
        ),
      ],
    ),
  );
}
