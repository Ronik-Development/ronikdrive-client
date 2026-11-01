import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/link.dart';
import 'package:url_launcher/url_launcher.dart';

import '../analytics/growth_analytics.dart';
import '../analytics/signup_completion_reconciliation.dart';
import '../billing/checkout_plan_intent.dart';
import '../documentation/user_documentation_page.dart';
import '../home/download_page.dart';
import '../home/tester_access_page.dart';
import '../shared/founding_user_perks.dart';
import '../shared/app_page_title.dart';
import '../shared/release_runtime_config.dart';
import 'login_page.dart';
import 'account_environment.dart';
import 'business_landing_page.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({
    super.key,
    required this.auth,
    required this.firestore,
    this.signupCompletionReconciler,
  });

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final SignupCompletionReconciler? signupCompletionReconciler;

  @override
  State<LandingPage> createState() => _LandingPageState();
}

enum BillingPeriod { monthly, yearly }

class _LandingPageState extends State<LandingPage> {
  late final GrowthAnalytics _growthAnalytics;
  late final GrowthAttribution _growthAttribution;
  late final GrowthSource _growthSource;
  BillingPeriod _selectedBillingPeriod = BillingPeriod.monthly;
  int _earlyAccessClaimed = 0;
  int _earlyAccessCapacity = foundingUserCapacity;
  bool _earlyAccessLoaded = false;

  @override
  void initState() {
    super.initState();
    _growthAnalytics = GrowthAnalytics();
    final attributionResolution = kIsWeb
        ? GrowthAttributionSession.instance.resolve(Uri.base)
        : const GrowthAttributionResolution(
            attribution: GrowthAttribution(
              source: GrowthSource.product,
              channel: GrowthChannel.product,
              entryPage: GrowthEntryPage.home,
            ),
            isNewEntry: true,
          );
    _growthAttribution = attributionResolution.attribution;
    _growthSource = _growthAttribution.source;
    if (attributionResolution.isNewEntry) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _recordGrowth(
          GrowthEvent.landingView,
          properties: GrowthEventProperties(
            surface: _growthSurface,
            channel: _growthAttribution.channel,
            entryPage: _growthAttribution.entryPage,
          ),
        );
      });
    }
    unawaited(_loadEarlyAccessSlots());
  }

  GrowthSurface get _growthSurface {
    if (kIsWeb) {
      return GrowthSurface.website;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return GrowthSurface.mobileApp;
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return GrowthSurface.desktopApp;
      case TargetPlatform.fuchsia:
        return GrowthSurface.unknown;
    }
  }

  GrowthBillingInterval get _growthBillingInterval =>
      _selectedBillingPeriod == BillingPeriod.monthly
      ? GrowthBillingInterval.monthly
      : GrowthBillingInterval.yearly;

  GrowthPlan _growthPlanForTier(String tier) {
    switch (tier) {
      case 'basic':
        return GrowthPlan.basic;
      case 'pro':
        return GrowthPlan.pro;
      case 'ultra':
        return GrowthPlan.ultra;
      default:
        return GrowthPlan.unknown;
    }
  }

  void _recordGrowth(
    GrowthEvent event, {
    GrowthEventProperties properties = const GrowthEventProperties(),
  }) {
    // Debug builds and widget tests must never pollute production reporting.
    if (!kReleaseMode) {
      return;
    }
    unawaited(
      _growthAnalytics.record(
        event: event,
        source: _growthSource,
        properties: properties,
      ),
    );
  }

  void _navigateToLogin(
    BuildContext context, {
    bool register = false,
    GrowthPlacement? signupPlacement,
    AccountEnvironment environment = AccountEnvironment.personal,
  }) {
    if (register && signupPlacement != null) {
      _recordGrowth(
        GrowthEvent.ctaClick,
        properties: GrowthEventProperties(
          placement: signupPlacement,
          channel: _growthAttribution.channel,
          entryPage: _growthAttribution.entryPage,
          ctaPlacement: growthCtaPlacementForLegacy(signupPlacement),
        ),
      );
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LoginPage(
          auth: widget.auth,
          firestore: widget.firestore,
          initialRegisterMode: register,
          initialEnvironment: environment,
          attribution: _growthAttribution,
          signupPlacement: signupPlacement ?? GrowthPlacement.unknown,
          signupCtaPlacement: signupPlacement == null
              ? GrowthCtaPlacement.unknown
              : growthCtaPlacementForLegacy(signupPlacement),
          signupCompletionReconciler: widget.signupCompletionReconciler,
        ),
      ),
    );
  }

  Uri _apiEndpoint(String path) {
    final baseUri = ReleaseRuntimeConfig.resolveCheckoutApiBaseUri();
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    return (baseUri.path.isEmpty || baseUri.path.endsWith('/'))
        ? baseUri.resolve(normalizedPath)
        : baseUri.replace(path: '${baseUri.path}/').resolve(normalizedPath);
  }

  Future<void> _loadEarlyAccessSlots() async {
    try {
      final response = await http
          .get(_apiEndpoint('early-access-slots'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return;
      }
      final claimed = _coerceCounterValue(decoded['claimed']);
      final capacity =
          _coerceCounterValue(decoded['capacity']) ?? foundingUserCapacity;
      if (!mounted) {
        return;
      }
      setState(() {
        _earlyAccessCapacity = capacity <= 0 ? foundingUserCapacity : capacity;
        _earlyAccessClaimed = (claimed ?? 0)
            .clamp(0, _earlyAccessCapacity)
            .toInt();
        _earlyAccessLoaded = true;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _earlyAccessLoaded = false;
      });
    }
  }

  int? _coerceCounterValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  Future<void> _showStarterPerksAndRegister(
    BuildContext context, {
    required String planTier,
    required String planTitle,
  }) async {
    _recordGrowth(
      GrowthEvent.pricingPlanSelected,
      properties: GrowthEventProperties(
        plan: _growthPlanForTier(planTier),
        billingInterval: _growthBillingInterval,
      ),
    );
    final foundingPerksAvailable =
        _earlyAccessLoaded && _earlyAccessClaimed < _earlyAccessCapacity;
    final shouldContinue = !foundingPerksAvailable
        ? true
        : await showDialog<bool>(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: Text('$planTitle selected'),
                content: const SingleChildScrollView(
                  child: FoundingUserPerksPanel(
                    subtitle:
                        'Before checkout, here is what the first 100 users get for helping shape RonikCloud.',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Not now'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Continue'),
                  ),
                ],
              );
            },
          );
    if (shouldContinue == true && context.mounted) {
      CheckoutPlanIntentStore.instance.remember(
        tier: planTier,
        interval: _selectedBillingPeriod == BillingPeriod.monthly
            ? 'monthly'
            : 'yearly',
      );
      _navigateToLogin(
        context,
        register: true,
        signupPlacement: GrowthPlacement.pricing,
      );
    }
  }

  void _openDownloadPage() {
    _recordGrowth(
      GrowthEvent.ctaClick,
      properties: GrowthEventProperties(
        placement: GrowthPlacement.downloadPage,
        channel: _growthAttribution.channel,
        entryPage: _growthAttribution.entryPage,
        ctaPlacement: GrowthCtaPlacement.inline,
      ),
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/download'),
        builder: (_) => DownloadPage(attribution: _growthAttribution),
      ),
    );
  }

  void _openBusinessPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/business'),
        builder: (_) => BusinessLandingPage(
          openAccount: (environment, register) async {
            _navigateToLogin(
              context,
              register: register,
              environment: environment,
            );
          },
        ),
      ),
    );
  }

  void _openTesterPage() {
    _recordGrowth(
      GrowthEvent.ctaClick,
      properties: GrowthEventProperties(
        placement: GrowthPlacement.testerPage,
        channel: _growthAttribution.channel,
        entryPage: _growthAttribution.entryPage,
        ctaPlacement: GrowthCtaPlacement.finalCta,
      ),
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/testers'),
        builder: (_) => TesterAccessPage(
          attribution: _growthAttribution,
          ctaPlacement: GrowthCtaPlacement.finalCta,
        ),
      ),
    );
  }

  void _openDocumentation() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const UserDocumentationPage()),
    );
  }

  Uri _publicPageUri(String path) {
    final publicBaseUri = kIsWeb && Uri.base.host.isNotEmpty
        ? Uri.base
        : ReleaseRuntimeConfig.resolveWebAppBaseUri(
            projectId: widget.auth.app.options.projectId,
          );
    return publicBaseUri.resolve(path);
  }

  Future<void> _openPublicPage(String path) async {
    await launchUrl(
      _publicPageUri(path),
      mode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
      webOnlyWindowName: kIsWeb ? '_self' : null,
    );
  }

  Widget _buildPublicTextLink({required String label, required String path}) {
    if (!kIsWeb) {
      return TextButton(
        onPressed: () => unawaited(_openPublicPage(path)),
        child: Text(label),
      );
    }
    return Link(
      uri: _publicPageUri(path),
      target: LinkTarget.self,
      builder: (context, followLink) =>
          TextButton(onPressed: followLink, child: Text(label)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wideLayout = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 56,
        centerTitle: false,
        titleSpacing: 16,
        title: !kIsWeb && defaultTargetPlatform == TargetPlatform.windows
            ? null
            : Row(
                children: [
                  Semantics(
                    label: 'RonikCloud home',
                    image: true,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png',
                        width: 32,
                        height: 32,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                ],
              ),
        actions: [
          if (wideLayout)
            TextButton(
              key: const ValueKey('landing-business-navigation'),
              onPressed: _openBusinessPage,
              child: const Text('Business'),
            ),
          if (wideLayout)
            TextButton(
              onPressed: _openDocumentation,
              child: const Text('Documentation'),
            )
          else
            IconButton(
              onPressed: _openDocumentation,
              tooltip: 'Documentation',
              icon: const Icon(Icons.menu_book_outlined),
            ),
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(80, 48),
              textStyle: const TextStyle(
                fontFamily: 'Source Sans 3',
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            onPressed: () => _navigateToLogin(context),
            child: const Text('Sign In'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 640;
          return SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 32),
                  child: Column(
                    children: [
                      _buildHeroSection(compact: compact),
                      _buildPricingSection(theme),
                      _buildDownloadSection(theme),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 32),
                        child: Column(
                          children: [
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                TextButton(
                                  onPressed: _openBusinessPage,
                                  child: const Text('Business'),
                                ),
                                _buildPublicTextLink(
                                  label: 'Resources',
                                  path: '/resources',
                                ),
                                _buildPublicTextLink(
                                  label: 'Security',
                                  path: '/secure-cloud-storage',
                                ),
                                _buildPublicTextLink(
                                  label: 'Encrypted sharing',
                                  path: '/encrypted-file-sharing',
                                ),
                                _buildPublicTextLink(
                                  label: 'For freelancers',
                                  path: '/for-freelancers',
                                ),
                                _buildPublicTextLink(
                                  label: 'For small teams',
                                  path: '/for-small-teams',
                                ),
                                _buildPublicTextLink(
                                  label: 'Downloads',
                                  path: '/download',
                                ),
                                _buildPublicTextLink(
                                  label: 'Tester program',
                                  path: '/testers',
                                ),
                                _buildPublicTextLink(
                                  label: 'Press kit',
                                  path: '/press-kit',
                                ),
                                _buildPublicTextLink(
                                  label: 'Support',
                                  path: '/support',
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '© 2026 RonikCloud.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ).withAppPageTitle(ronikCloudHomeTitle);
  }

  Widget _buildHeroSection({required bool compact}) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 56 : 96),
      child: Column(
        key: const ValueKey('landing-hero'),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Text(
              'Your files.\nYour private space.',
              textAlign: TextAlign.center,
              style:
                  (compact
                          ? theme.textTheme.displaySmall
                          : theme.textTheme.displayLarge)
                      ?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.08,
                        letterSpacing: -1.5,
                      ),
            ),
          ),
          const SizedBox(height: 24),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 510),
            child: Text(
              'Store, back up, and share your work. Encrypted on your device before it reaches the cloud.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 32),
          FilledButton(
            key: const ValueKey('landing-primary-actions'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            ),
            onPressed: () => _navigateToLogin(
              context,
              register: true,
              signupPlacement: GrowthPlacement.hero,
            ),
            child: const Text('Create free workspace'),
          ),
          const SizedBox(height: 16),
          Text(
            '1 GB free. No credit card required.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            key: const ValueKey('landing-business-link'),
            onPressed: _openBusinessPage,
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Text('Compare Personal and Business'),
          ),
        ],
      ),
    );
  }

  Widget _buildPricingSection(ThemeData theme) {
    final isMonthly = _selectedBillingPeriod == BillingPeriod.monthly;

    return Padding(
      key: const ValueKey('landing-pricing-section'),
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 40),
      child: Column(
        children: [
          Text(
            'Room to grow',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start free. Upgrade when you need more space.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          SegmentedButton<BillingPeriod>(
            segments: const [
              ButtonSegment(
                value: BillingPeriod.monthly,
                label: Text('Monthly'),
              ),
              ButtonSegment(value: BillingPeriod.yearly, label: Text('Yearly')),
            ],
            selected: {_selectedBillingPeriod},
            onSelectionChanged: (selection) {
              final selectedPeriod = selection.first;
              setState(() => _selectedBillingPeriod = selectedPeriod);
              _recordGrowth(
                GrowthEvent.pricingPeriodSelected,
                properties: GrowthEventProperties(
                  billingInterval: selectedPeriod == BillingPeriod.monthly
                      ? GrowthBillingInterval.monthly
                      : GrowthBillingInterval.yearly,
                ),
              );
            },
          ),
          const SizedBox(height: 40),
          _LandingCardRow(
            children: [
              _PricingCard(
                title: 'Basic',
                price: isMonthly ? '\$2.50' : '\$25',
                period: isMonthly ? '/month' : '/year',
                features: const [
                  '500 GB encrypted storage',
                  'Protected links and file requests',
                  'Guided cloud imports',
                ],
                highlighted: true,
                onTap: () => _showStarterPerksAndRegister(
                  context,
                  planTier: 'basic',
                  planTitle: 'Basic',
                ),
              ),
              _PricingCard(
                title: 'Pro',
                price: isMonthly ? '\$3.50' : '\$35',
                period: isMonthly ? '/month' : '/year',
                features: const [
                  '1 TB encrypted storage',
                  'Protected links and file requests',
                  'Encrypted collaboration tools',
                  'Guided cloud imports',
                ],
                onTap: () => _showStarterPerksAndRegister(
                  context,
                  planTier: 'pro',
                  planTitle: 'Pro',
                ),
              ),
              _PricingCard(
                title: 'Ultra',
                price: isMonthly ? '\$6' : '\$60',
                period: isMonthly ? '/month' : '/year',
                features: const [
                  '2 TB encrypted storage',
                  'Protected links and file requests',
                  'Encrypted collaboration tools',
                  'Guided cloud imports',
                ],
                onTap: () => _showStarterPerksAndRegister(
                  context,
                  planTier: 'ultra',
                  planTitle: 'Ultra',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadSection(ThemeData theme) {
    return Padding(
      key: const ValueKey('landing-download-section'),
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 40),
      child: Column(
        children: [
          Text(
            'Get the app',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Use the web app now, or check the current mobile and desktop releases.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _openDownloadPage,
                icon: const Icon(Icons.download_rounded),
                label: const Text('See current downloads'),
              ),
              TextButton.icon(
                onPressed: _openTesterPage,
                icon: const Icon(Icons.science_outlined),
                label: const Text('Join release testing'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Equal-height desktop rows; natural-height stacked cards on small screens.
class _LandingCardRow extends StatelessWidget {
  const _LandingCardRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth >= 900 &&
          MediaQuery.textScalerOf(context).scale(14) <= 21) {
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0) const SizedBox(width: 16),
                Expanded(child: children[index]),
              ],
            ],
          ),
        );
      }
      return Column(
        children: [
          for (final child in children)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SizedBox(
                width: constraints.maxWidth.clamp(0, 420),
                child: IntrinsicHeight(child: child),
              ),
            ),
        ],
      );
    },
  );
}

class _PricingCard extends StatelessWidget {
  const _PricingCard({
    required this.title,
    required this.price,
    required this.period,
    required this.features,
    required this.onTap,
    this.highlighted = false,
  });

  final String title;
  final String price;
  final String period;
  final List<String> features;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SizedBox(
      width: double.infinity,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: highlighted
              ? BorderSide(color: colorScheme.primary, width: 2)
              : BorderSide(color: colorScheme.outlineVariant, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Visibility(
                visible: highlighted,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Lowest price',
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        price,
                        style: theme.textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                      Text(period, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ...features.map(
                (feature) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.check, size: 16, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(feature, style: theme.textTheme.bodyMedium),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: onTap,
                  child: const Text('Choose Plan'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
