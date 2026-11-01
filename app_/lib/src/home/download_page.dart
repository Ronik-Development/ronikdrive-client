import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../analytics/growth_analytics.dart';
import '../shared/app_page_title.dart';
import '../shared/release_runtime_config.dart';
import 'tester_access_page.dart';

final _windowsInstallerDownloadUri = Uri.https(
  'github.com',
  '/Ronik-Development/ronikcloud-releases/releases/latest/download/ronikcloud-windows-setup.exe',
);

Uri downloadUriForPlatform({
  required String platform,
  required Uri apiBaseUri,
  required GrowthChannel channel,
}) {
  return apiBaseUri
      .resolve('downloads/$platform')
      .replace(queryParameters: <String, String>{'channel': channel.wireName});
}

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key, this.client, this.attribution});

  final http.Client? client;
  final GrowthAttribution? attribution;

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  final Map<String, bool> _availableDownloads = <String, bool>{};
  final GrowthAnalytics _growthAnalytics = GrowthAnalytics();

  late final GrowthAttribution _growthAttribution;
  bool _loadingStatus = true;
  bool _statusFailed = false;
  String? _desktopReleaseLabel;

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

  Uri get _apiBaseUri => ReleaseRuntimeConfig.resolveDownloadApiBaseUri();

  Uri get _publicDownloadsBaseUri {
    if (kIsWeb && Uri.base.hasScheme && Uri.base.host.isNotEmpty) {
      return Uri.base;
    }
    return ReleaseRuntimeConfig.resolveWebAppBaseUri(
      projectId: ReleaseRuntimeConfig.defaultWebProjectId,
    );
  }

  Future<http.Response> _get(Uri uri) {
    return widget.client?.get(uri) ?? http.get(uri);
  }

  @override
  void initState() {
    super.initState();
    late final bool shouldRecordEntryView;
    if (widget.attribution != null) {
      _growthAttribution = widget.attribution!;
      shouldRecordEntryView = false;
    } else if (kIsWeb) {
      final resolution = GrowthAttributionSession.instance.resolve(Uri.base);
      _growthAttribution = resolution.attribution;
      shouldRecordEntryView = resolution.isNewEntry;
    } else {
      _growthAttribution = const GrowthAttribution(
        source: GrowthSource.product,
        channel: GrowthChannel.product,
        entryPage: GrowthEntryPage.download,
      );
      shouldRecordEntryView = true;
    }
    if (shouldRecordEntryView && kReleaseMode) {
      unawaited(
        _growthAnalytics.record(
          event: GrowthEvent.landingView,
          source: _growthAttribution.source,
          properties: GrowthEventProperties(
            channel: _growthAttribution.channel,
            entryPage: _growthAttribution.entryPage,
            surface: _growthSurface,
          ),
        ),
      );
    }
    unawaited(_loadDownloadStatus());
    unawaited(_loadDesktopReleaseMetadata());
  }

  Future<void> _loadDownloadStatus() async {
    if (!_loadingStatus && mounted) {
      setState(() {
        _loadingStatus = true;
        _statusFailed = false;
      });
    }
    try {
      final response = await _get(
        _apiBaseUri.resolve('downloads/status'),
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw StateError('Status ${response.statusCode}');
      }
      final decoded = jsonDecode(response.body);
      final platforms = decoded is Map ? decoded['platforms'] : null;
      if (platforms is! Map) {
        throw const FormatException('Missing platform status.');
      }
      final availability = <String, bool>{};
      for (final entry in platforms.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        availability[key] = value is Map && value['available'] == true;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _availableDownloads
          ..clear()
          ..addAll(availability);
        _loadingStatus = false;
        _statusFailed = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingStatus = false;
        _statusFailed = true;
      });
    }
  }

  Future<void> _loadDesktopReleaseMetadata() async {
    try {
      final response = await _get(
        _publicDownloadsBaseUri.resolve(
          '/downloads/latest/release-manifest.json',
        ),
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        return;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return;
      }
      final version = decoded['version']?.toString().trim() ?? '';
      final buildNumber = decoded['buildNumber']?.toString().trim() ?? '';
      if (version.isEmpty || !mounted) {
        return;
      }
      setState(() {
        _desktopReleaseLabel = buildNumber.isEmpty
            ? 'Version $version'
            : 'Version $version (build $buildNumber)';
      });
    } catch (_) {
      // Direct desktop downloads remain usable without optional metadata.
    }
  }

  Future<void> _launchDownload(String platform) async {
    final uri = downloadUriForPlatform(
      platform: platform,
      apiBaseUri: _apiBaseUri,
      channel: _growthAttribution.channel,
    );
    await _launchUri(uri, platform);
  }

  Future<void> _launchUri(Uri uri, String platform) async {
    var launched = false;
    try {
      launched = await launchUrl(
        uri,
        mode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
        webOnlyWindowName: kIsWeb ? '_self' : null,
      );
    } on Object {
      // Missing platform handlers use the same visible recovery as a refusal.
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not start the $platform download. Please try again.',
          ),
        ),
      );
    }
  }

  String _desktopDescription(String archiveType) {
    final release = _desktopReleaseLabel;
    if (release == null) {
      return 'Direct $archiveType download from this site';
    }
    return '$release - Direct $archiveType download';
  }

  void _openTesterPage() {
    if (kReleaseMode) {
      unawaited(
        _growthAnalytics.record(
          event: GrowthEvent.ctaClick,
          source: _growthAttribution.source,
          properties: GrowthEventProperties(
            placement: GrowthPlacement.testerPage,
            channel: _growthAttribution.channel,
            entryPage: _growthAttribution.entryPage,
            ctaPlacement: GrowthCtaPlacement.inline,
          ),
        ),
      );
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/testers'),
        builder: (_) => TesterAccessPage(
          attribution: _growthAttribution,
          ctaPlacement: GrowthCtaPlacement.inline,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Get RonikCloud')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (!_loadingStatus &&
                  !_statusFailed &&
                  _availableDownloads[defaultTargetPlatform.name] == true) ...[
                FilledButton.icon(
                  onPressed: () => _launchDownload(defaultTargetPlatform.name),
                  icon: const Icon(Icons.download),
                  label: Text(
                    'Get RonikCloud for ${defaultTargetPlatform.name}',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  defaultTargetPlatform == TargetPlatform.windows
                      ? 'Download the ZIP, extract all files, then open RonikCloud from the extracted folder.'
                      : 'Open the download or testing invitation and follow the installation instructions.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
              ],
              Text(
                'Download RonikCloud',
                style: theme.textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Choose your device below. Already have an account? Sign in after installing to access your files.',
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _openTesterPage,
                icon: const Icon(Icons.science_outlined),
                label: const Text('Join the tester program'),
              ),
              const SizedBox(height: 24),
              Text('Downloads', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Desktop packages appear here as soon as a verified public build is published.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              if (_loadingStatus) ...[
                const LinearProgressIndicator(
                  semanticsLabel: 'Checking download availability',
                ),
                const SizedBox(height: 16),
              ],
              if (_statusFailed) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    'Could not check download availability. Check your connection and try again.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => unawaited(_loadDownloadStatus()),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry availability'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _DownloadCard(
                icon: Icons.desktop_windows,
                title: 'Windows',
                description:
                    '${_desktopDescription('ZIP')}. This Windows release is unsigned; Windows may show an unknown-publisher warning.',
                unavailableDescription:
                    'Temporarily unavailable while the latest verified build is published.',
                actionLabel: 'Download portable ZIP',
                available: _availableDownloads['windows'],
                loading: _loadingStatus,
                statusFailed: _statusFailed,
                onTap: () => _launchDownload('windows'),
                isPrimary: defaultTargetPlatform == TargetPlatform.windows,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey<String>('Windows-installer-action'),
                  onPressed:
                      !_loadingStatus &&
                          !_statusFailed &&
                          _availableDownloads['windows'] == true
                      ? () => _launchUri(
                          _windowsInstallerDownloadUri,
                          'Windows installer',
                        )
                      : null,
                  icon: const Icon(Icons.install_desktop_outlined),
                  label: const Text('Download Windows installer'),
                ),
              ),
              const SizedBox(height: 16),
              _DownloadCard(
                icon: Icons.computer,
                title: 'Linux',
                description: _desktopDescription('tar.gz'),
                unavailableDescription:
                    'Temporarily unavailable while the latest verified build is published.',
                actionLabel: 'Download tar.gz',
                available: _availableDownloads['linux'],
                loading: _loadingStatus,
                statusFailed: _statusFailed,
                onTap: () => _launchDownload('linux'),
                isPrimary: defaultTargetPlatform == TargetPlatform.linux,
              ),
              const SizedBox(height: 32),
              Text(
                'Mobile and Apple testing',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              _DownloadCard(
                icon: Icons.android,
                title: 'Android',
                description: 'Join the Android beta',
                actionLabel: 'Open beta',
                available: _availableDownloads['android'],
                loading: _loadingStatus,
                statusFailed: _statusFailed,
                onTap: () => _launchDownload('android'),
                isPrimary: defaultTargetPlatform == TargetPlatform.android,
              ),
              const SizedBox(height: 16),
              _DownloadCard(
                icon: Icons.apple,
                title: 'macOS',
                description: 'Join the macOS TestFlight beta',
                actionLabel: 'Open TestFlight',
                available: _availableDownloads['macos'],
                loading: _loadingStatus,
                statusFailed: _statusFailed,
                onTap: () => _launchDownload('macos'),
                isPrimary: defaultTargetPlatform == TargetPlatform.macOS,
              ),
              const SizedBox(height: 16),
              _DownloadCard(
                icon: Icons.phone_iphone,
                title: 'iOS',
                description: 'TestFlight invite required',
                actionLabel: 'Open TestFlight',
                available: _availableDownloads['ios'],
                loading: _loadingStatus,
                statusFailed: _statusFailed,
                onTap: () => _launchDownload('ios'),
              ),
            ],
          ),
        ),
      ),
    ).withAppPageTitle(
      'Download RonikCloud | Current Apps and Install Options',
    );
  }
}

class _DownloadCard extends StatelessWidget {
  const _DownloadCard({
    required this.icon,
    required this.title,
    required this.description,
    this.unavailableDescription,
    required this.actionLabel,
    required this.available,
    required this.loading,
    required this.statusFailed,
    required this.onTap,
    this.isPrimary = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? unavailableDescription;
  final String actionLabel;
  final bool? available;
  final bool loading;
  final bool statusFailed;
  final VoidCallback onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabled = available == true && !loading && !statusFailed;
    final statusUnknown = statusFailed || available == null;
    final detail = loading
        ? 'Checking availability…'
        : statusUnknown
        ? 'Availability could not be confirmed. Try checking again.'
        : enabled
        ? description
        : unavailableDescription ?? '$description. Join the tester list first.';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isPrimary
            ? BorderSide(color: colorScheme.primary, width: 2)
            : BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxWidth < 460 ||
                MediaQuery.textScalerOf(context).scale(14) > 21;
            final information = Row(
              children: [
                Icon(
                  icon,
                  size: 32,
                  color: enabled
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        detail,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
            final action = FilledButton.tonalIcon(
              key: ValueKey<String>('$title-download-action'),
              onPressed: enabled ? onTap : null,
              icon: Icon(
                enabled
                    ? Icons.download_outlined
                    : loading || statusUnknown
                    ? Icons.hourglass_empty
                    : Icons.lock_clock_outlined,
              ),
              label: Text(
                enabled
                    ? actionLabel
                    : loading
                    ? 'Checking…'
                    : statusUnknown
                    ? 'Status unknown'
                    : 'Not available',
              ),
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [information, const SizedBox(height: 16), action],
              );
            }
            return Row(
              children: [
                Expanded(child: information),
                const SizedBox(width: 16),
                action,
              ],
            );
          },
        ),
      ),
    );
  }
}

