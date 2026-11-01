import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../analytics/growth_analytics.dart';
import '../shared/app_page_title.dart';
import '../shared/release_runtime_config.dart';

const String testerReferralUrl =
    'https://ronikcloud.com/testers?utm_source=user_referral&'
    'utm_medium=referral&utm_campaign=founding_beta_2026&'
    'utm_content=tester_success';

typedef TesterReferralShareHandler =
    Future<void> Function(String message, Rect sharePositionOrigin);
typedef TesterGrowthEventRecorder =
    Future<void> Function({
      required GrowthEvent event,
      required GrowthSource source,
      required GrowthEventProperties properties,
    });

class TesterAccessPage extends StatefulWidget {
  const TesterAccessPage({
    super.key,
    this.client,
    this.campaignUri,
    this.attribution,
    this.growthSource,
    this.ctaPlacement,
    this.referralShareHandler,
    this.growthEventRecorder,
  }) : assert(
         (campaignUri == null ? 0 : 1) +
                 (attribution == null ? 0 : 1) +
                 (growthSource == null ? 0 : 1) <=
             1,
         'Pass only one of campaignUri, attribution, or growthSource.',
       );

  final http.Client? client;

  /// The browser URL that brought the visitor to this page.
  ///
  /// Only fixed [GrowthSource] and [GrowthChannel] values are derived from this
  /// value. Raw UTM values and the URL itself are never sent with the request.
  final Uri? campaignUri;

  /// First-touch attribution handed across an in-app navigation.
  final GrowthAttribution? attribution;

  /// Legacy coarse-source injection retained for existing callers.
  final GrowthSource? growthSource;

  /// The fixed CTA location that brought the visitor to this tester form.
  final GrowthCtaPlacement? ctaPlacement;

  /// Optional injection point used by widget tests to avoid opening an OS share
  /// sheet. Production callers use [Share.share].
  final TesterReferralShareHandler? referralShareHandler;

  /// Optional aggregate event recorder used by widget tests. Production
  /// release builds use [GrowthAnalytics] directly.
  final TesterGrowthEventRecorder? growthEventRecorder;

  @override
  State<TesterAccessPage> createState() => _TesterAccessPageState();
}

class _TesterAccessPageState extends State<TesterAccessPage> {
  final TextEditingController _emailController = TextEditingController();
  final Map<String, bool> _availableDownloads = <String, bool>{};
  final GlobalKey _referralShareAnchorKey = GlobalKey(
    debugLabel: 'tester-referral-share-anchor',
  );

  late final GrowthAnalytics _growthAnalytics;
  late final GrowthAttribution _growthAttribution;
  late final GrowthCtaPlacement _ctaPlacement;
  bool _wantsProductNews = false;
  bool _wantsTesting = true;
  bool _submitting = false;
  bool _success = false;
  bool _testingOptInSucceeded = false;
  bool _loadingPlatformStatus = true;
  bool _platformStatusLoaded = false;
  bool _testerSignupStartedRecorded = false;
  String? _message;

  GrowthSource get _growthSource => _growthAttribution.source;

  @override
  void initState() {
    super.initState();
    _growthAnalytics = GrowthAnalytics();
    final campaignUri = widget.campaignUri ?? (kIsWeb ? Uri.base : null);
    late final bool shouldRecordEntryView;
    if (widget.attribution != null) {
      _growthAttribution = widget.attribution!;
      shouldRecordEntryView = false;
    } else if (widget.growthSource != null) {
      _growthAttribution = GrowthAttribution(
        source: widget.growthSource!,
        channel: growthChannelForLegacySource(widget.growthSource!),
        entryPage: GrowthEntryPage.testers,
      );
      shouldRecordEntryView = false;
    } else if (campaignUri != null) {
      if (kIsWeb) {
        final resolution = GrowthAttributionSession.instance.resolve(
          campaignUri,
        );
        _growthAttribution = resolution.attribution;
        shouldRecordEntryView = resolution.isNewEntry;
      } else {
        _growthAttribution = growthAttributionFromUri(campaignUri);
        shouldRecordEntryView = true;
      }
    } else {
      _growthAttribution = const GrowthAttribution(
        source: GrowthSource.product,
        channel: GrowthChannel.product,
        entryPage: GrowthEntryPage.testers,
      );
      shouldRecordEntryView = true;
    }
    _ctaPlacement =
        widget.ctaPlacement ??
        (campaignUri == null
            ? GrowthCtaPlacement.direct
            : growthCtaPlacementFromCampaignUri(campaignUri));
    if (shouldRecordEntryView) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(
            _recordGrowth(
              GrowthEvent.landingView,
              properties: GrowthEventProperties(
                channel: _growthAttribution.channel,
                entryPage: _growthAttribution.entryPage,
                surface: _growthSurface,
              ),
            ),
          );
        }
      });
    }
    unawaited(_loadPlatformStatus());
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

  Future<void> _recordGrowth(
    GrowthEvent event, {
    required GrowthEventProperties properties,
  }) async {
    final injectedRecorder = widget.growthEventRecorder;
    if (!kReleaseMode && injectedRecorder == null) {
      return;
    }
    try {
      if (injectedRecorder != null) {
        await injectedRecorder(
          event: event,
          source: _growthSource,
          properties: properties,
        );
        return;
      }
      await _growthAnalytics.record(
        event: event,
        source: _growthSource,
        properties: properties,
      );
    } on Object {
      // Aggregate analytics must never block or reverse a successful signup.
    }
  }

  Rect _referralSharePositionOrigin() {
    final renderObject = _referralShareAnchorKey.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      throw StateError('The referral share anchor is unavailable.');
    }
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  Future<void> _shareReferralWithPlatform(
    String message,
    Rect sharePositionOrigin,
  ) async {
    await Share.share(message, sharePositionOrigin: sharePositionOrigin);
  }

  Future<void> _shareReferral() async {
    final strings = AppLocalizations.of(context)!;
    final message = '${strings.testerReferralShareText}\n\n$testerReferralUrl';
    unawaited(
      _recordGrowth(
        GrowthEvent.ctaClick,
        properties: GrowthEventProperties(
          placement: GrowthPlacement.testerReferral,
          channel: _growthAttribution.channel,
          entryPage: _growthAttribution.entryPage,
          ctaPlacement: GrowthCtaPlacement.postSignupReferral,
        ),
      ),
    );
    try {
      final sharePositionOrigin = _referralSharePositionOrigin();
      await (widget.referralShareHandler ?? _shareReferralWithPlatform)(
        message,
        sharePositionOrigin,
      );
    } on Object {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.testerReferralShareFailure)),
      );
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Uri _apiEndpoint(String path) {
    final baseUri = ReleaseRuntimeConfig.resolveCheckoutApiBaseUri();
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    return (baseUri.path.isEmpty || baseUri.path.endsWith('/'))
        ? baseUri.resolve(normalizedPath)
        : baseUri.replace(path: '${baseUri.path}/').resolve(normalizedPath);
  }

  Future<http.Response> _get(Uri uri) {
    return widget.client?.get(uri) ?? http.get(uri);
  }

  Future<http.Response> _post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return widget.client?.post(uri, headers: headers, body: body) ??
        http.post(uri, headers: headers, body: body);
  }

  Future<void> _loadPlatformStatus() async {
    try {
      final response = await _get(
        _apiEndpoint('downloads/status'),
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw StateError('Unexpected download status response.');
      }
      final decoded = jsonDecode(response.body);
      final platforms = decoded is Map ? decoded['platforms'] : null;
      if (platforms is! Map) {
        throw const FormatException('Missing platform status.');
      }
      final availability = <String, bool>{};
      for (final entry in platforms.entries) {
        final value = entry.value;
        availability[entry.key.toString()] =
            value is Map && value['available'] == true;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _availableDownloads
          ..clear()
          ..addAll(availability);
        _loadingPlatformStatus = false;
        _platformStatusLoaded = true;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingPlatformStatus = false;
        _platformStatusLoaded = false;
      });
    }
  }

  String _failureMessage(AppLocalizations strings, int? httpStatus) {
    return switch (httpStatus) {
      400 => strings.testerFailureInvalid,
      409 => strings.testerFailureAlreadyRegistered,
      429 => strings.testerFailureRateLimited,
      502 || 503 || 504 => strings.testerFailureUnavailable,
      _ => strings.testerFailureGeneric,
    };
  }

  Future<void> _submit() async {
    final strings = AppLocalizations.of(context)!;
    final email = _emailController.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() {
        _success = false;
        _testingOptInSucceeded = false;
        _message = strings.testerInvalidEmail;
      });
      return;
    }
    if (!_wantsProductNews && !_wantsTesting) {
      setState(() {
        _success = false;
        _testingOptInSucceeded = false;
        _message = strings.testerChoosePreference;
      });
      return;
    }

    setState(() {
      _submitting = true;
      _success = false;
      _testingOptInSucceeded = false;
      _message = null;
    });

    if (_wantsTesting && !_testerSignupStartedRecorded) {
      _testerSignupStartedRecorded = true;
      unawaited(
        _recordGrowth(
          GrowthEvent.testerSignupStarted,
          properties: GrowthEventProperties(
            placement: GrowthPlacement.testerPage,
            channel: _growthAttribution.channel,
            entryPage: _growthAttribution.entryPage,
            ctaPlacement: _ctaPlacement,
          ),
        ),
      );
    }

    try {
      final response = await _post(
        _apiEndpoint('tester-signups'),
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, dynamic>{
          'email': email,
          'source': 'testers_page',
          'growthSource': _growthSource.wireName,
          'channel': _growthAttribution.channel.wireName,
          'entryPage': _growthAttribution.entryPage.wireName,
          'ctaPlacement': _ctaPlacement.wireName,
          'wantsProductNews': _wantsProductNews,
          'wantsTesting': _wantsTesting,
        }),
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (!mounted) {
          return;
        }
        setState(() {
          _success = false;
          _testingOptInSucceeded = false;
          _message = _failureMessage(strings, response.statusCode);
        });
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _success = true;
        _testingOptInSucceeded = _wantsTesting;
        _message = _wantsTesting
            ? strings.testerSuccessTesting
            : strings.testerSuccessNews;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _success = false;
        _testingOptInSucceeded = false;
        _message = _failureMessage(strings, null);
      });
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(strings.testerPageTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            children: [
              Semantics(
                header: true,
                child: Text(
                  strings.testerEyebrow,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                strings.testerHeroTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                strings.testerHeroBody,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              Text(
                strings.testerHeroAsk,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              _TesterSignupForm(
                controller: _emailController,
                submitting: _submitting,
                success: _success,
                showReferral: _testingOptInSucceeded,
                message: _message,
                wantsProductNews: _wantsProductNews,
                wantsTesting: _wantsTesting,
                onWantsProductNewsChanged: (value) {
                  setState(() => _wantsProductNews = value);
                },
                onWantsTestingChanged: (value) {
                  setState(() => _wantsTesting = value);
                },
                onSubmit: () => unawaited(_submit()),
                onShareReferral: () => unawaited(_shareReferral()),
                referralShareAnchorKey: _referralShareAnchorKey,
              ),
              const SizedBox(height: 24),
              const _TesterWorkflowCard(),
              const SizedBox(height: 16),
              const _BetaBoundaryCard(),
              const SizedBox(height: 16),
              _TestingChannelSummary(
                availability: _availableDownloads,
                loading: _loadingPlatformStatus,
                loaded: _platformStatusLoaded,
              ),
              const SizedBox(height: 16),
              Align(
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).pushNamed('/download'),
                  icon: const Icon(Icons.download_outlined),
                  label: Text(strings.testerCheckDownloads),
                ),
              ),
            ],
          ),
        ),
      ),
    ).withAppPageTitle('Join the RonikCloud Founding Beta | Become a Tester');
  }
}

class _TesterWorkflowCard extends StatelessWidget {
  const _TesterWorkflowCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppLocalizations.of(context)!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.testerWorkflowTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            _WorkflowStep(
              number: 1,
              title: strings.testerStepOneTitle,
              detail: strings.testerStepOneDetail,
            ),
            _WorkflowStep(
              number: 2,
              title: strings.testerStepTwoTitle,
              detail: strings.testerStepTwoDetail,
            ),
            _WorkflowStep(
              number: 3,
              title: strings.testerStepThreeTitle,
              detail: strings.testerStepThreeDetail,
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkflowStep extends StatelessWidget {
  const _WorkflowStep({
    required this.number,
    required this.title,
    required this.detail,
  });

  final int number;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.onPrimaryContainer,
            child: Text(
              '$number',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BetaBoundaryCard extends StatelessWidget {
  const _BetaBoundaryCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final strings = AppLocalizations.of(context)!;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
        color: colorScheme.tertiaryContainer.withValues(alpha: 0.35),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: colorScheme.onTertiaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.testerBoundariesTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colorScheme.onTertiaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    strings.testerBoundariesBody,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onTertiaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TestingChannelSummary extends StatelessWidget {
  const _TestingChannelSummary({
    required this.availability,
    required this.loading,
    required this.loaded,
  });

  final Map<String, bool> availability;
  final bool loading;
  final bool loaded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppLocalizations.of(context)!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.testerPlatformsTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              strings.testerPlatformsBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            _ChannelLine(
              icon: Icons.android_rounded,
              title: strings.testerPlatformAndroid,
              detail: strings.testerChannelGooglePlay,
              available: availability['android'],
              loading: loading,
              loaded: loaded,
            ),
            _ChannelLine(
              icon: Icons.phone_iphone_rounded,
              title: strings.testerPlatformIos,
              detail: strings.testerChannelTestFlight,
              available: availability['ios'],
              loading: loading,
              loaded: loaded,
            ),
            _ChannelLine(
              icon: Icons.apple_rounded,
              title: strings.testerPlatformMacos,
              detail: strings.testerChannelTestFlight,
              available: availability['macos'],
              loading: loading,
              loaded: loaded,
            ),
            _ChannelLine(
              icon: Icons.desktop_windows_rounded,
              title: strings.testerPlatformWindows,
              detail: strings.testerChannelDirectDownload,
              available: availability['windows'],
              loading: loading,
              loaded: loaded,
            ),
            _ChannelLine(
              icon: Icons.computer_rounded,
              title: strings.testerPlatformLinux,
              detail: strings.testerChannelDirectDownload,
              available: availability['linux'],
              loading: loading,
              loaded: loaded,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelLine extends StatelessWidget {
  const _ChannelLine({
    required this.icon,
    required this.title,
    required this.detail,
    required this.available,
    required this.loading,
    required this.loaded,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool? available;
  final bool loading;
  final bool loaded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppLocalizations.of(context)!;
    final status = loading
        ? strings.testerAvailabilityChecking
        : !loaded || available == null
        ? strings.testerAvailabilityUnknown
        : available == true
        ? strings.testerAvailabilityAvailable
        : strings.testerAvailabilityUnavailable;
    final statusColor = loaded && available == true
        ? theme.brightness == Brightness.dark
              ? const Color(0xFF86EFAC)
              : const Color(0xFF166534)
        : theme.colorScheme.onSurfaceVariant;
    final statusLabel = Text(
      status,
      style: theme.textTheme.labelMedium?.copyWith(
        color: statusColor,
        fontWeight: FontWeight.w700,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < 420 ||
              MediaQuery.textScalerOf(context).scale(14) > 21;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      detail,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (compact) ...[const SizedBox(height: 4), statusLabel],
                  ],
                ),
              ),
              if (!compact) ...[const SizedBox(width: 12), statusLabel],
            ],
          );
        },
      ),
    );
  }
}

class _TesterSignupForm extends StatelessWidget {
  const _TesterSignupForm({
    required this.controller,
    required this.submitting,
    required this.success,
    required this.showReferral,
    required this.message,
    required this.wantsProductNews,
    required this.wantsTesting,
    required this.onWantsProductNewsChanged,
    required this.onWantsTestingChanged,
    required this.onSubmit,
    required this.onShareReferral,
    required this.referralShareAnchorKey,
  });

  final TextEditingController controller;
  final bool submitting;
  final bool success;
  final bool showReferral;
  final String? message;
  final bool wantsProductNews;
  final bool wantsTesting;
  final ValueChanged<bool> onWantsProductNewsChanged;
  final ValueChanged<bool> onWantsTestingChanged;
  final VoidCallback onSubmit;
  final VoidCallback onShareReferral;
  final GlobalKey referralShareAnchorKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final strings = AppLocalizations.of(context)!;
    final successColor = theme.brightness == Brightness.dark
        ? const Color(0xFF86EFAC)
        : const Color(0xFF166534);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary, width: 1.5),
        color: colorScheme.primaryContainer.withValues(alpha: 0.22),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.science_outlined, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    strings.testerFormTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              strings.testerFormBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact =
                    constraints.maxWidth < 520 ||
                    MediaQuery.textScalerOf(context).scale(14) > 21;
                final field = TextField(
                  key: const ValueKey<String>('tester-email-field'),
                  controller: controller,
                  enabled: !submitting,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.send,
                  autofillHints: const [AutofillHints.email],
                  onSubmitted: (_) {
                    if (!submitting) {
                      onSubmit();
                    }
                  },
                  decoration: InputDecoration(
                    labelText: strings.testerEmailLabel,
                    hintText: strings.testerEmailHint,
                    prefixIcon: const Icon(Icons.alternate_email),
                    border: const OutlineInputBorder(),
                  ),
                );
                final button = FilledButton.icon(
                  key: const ValueKey<String>('tester-submit'),
                  onPressed: submitting ? null : onSubmit,
                  icon: submitting
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.primary,
                          ),
                        )
                      : const Icon(Icons.mail_outline, size: 20),
                  label: Text(
                    submitting
                        ? strings.testerSubmitting
                        : strings.testerSubmit,
                  ),
                );

                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [field, const SizedBox(height: 12), button],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: field),
                    const SizedBox(width: 12),
                    SizedBox(height: 56, child: button),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: wantsTesting,
              onChanged: submitting ? null : onWantsTestingChanged,
              title: Text(strings.testerTestingTitle),
              subtitle: Text(strings.testerTestingSubtitle),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: wantsProductNews,
              onChanged: submitting ? null : onWantsProductNewsChanged,
              title: Text(strings.testerProductNewsTitle),
              subtitle: Text(strings.testerProductNewsSubtitle),
            ),
            const SizedBox(height: 4),
            Text(
              strings.testerConsentNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      success ? Icons.check_circle : Icons.error_outline,
                      color: success ? successColor : colorScheme.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: success ? successColor : colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (showReferral) ...[
              const SizedBox(height: 16),
              _TesterReferralPrompt(
                onShare: onShareReferral,
                shareAnchorKey: referralShareAnchorKey,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TesterReferralPrompt extends StatelessWidget {
  const _TesterReferralPrompt({
    required this.onShare,
    required this.shareAnchorKey,
  });

  final VoidCallback onShare;
  final GlobalKey shareAnchorKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final strings = AppLocalizations.of(context)!;
    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.outlineVariant),
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.testerReferralTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                strings.testerReferralBody,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                key: shareAnchorKey,
                child: OutlinedButton.icon(
                  key: const ValueKey<String>('tester-referral-share'),
                  onPressed: onShare,
                  icon: const Icon(Icons.ios_share_outlined),
                  label: Text(strings.testerReferralButton),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
