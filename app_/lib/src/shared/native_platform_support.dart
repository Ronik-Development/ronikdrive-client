import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_theme.dart';
import 'release_runtime_config.dart';

/// Match the native plugins and registered Linux user-token cloud adapters.
bool supportsCloudRuntime({
  required bool isWeb,
  required TargetPlatform platform,
}) =>
    isWeb ||
    switch (platform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      TargetPlatform.fuchsia => false,
    };

class UnsupportedNativePlatformApp extends StatelessWidget {
  const UnsupportedNativePlatformApp({super.key, this.openWebApp});

  final Future<bool> Function()? openWebApp;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'RonikCloud',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    home: _BrowserFallbackPage(openWebApp: openWebApp),
  );
}

class _BrowserFallbackPage extends StatefulWidget {
  const _BrowserFallbackPage({this.openWebApp});

  final Future<bool> Function()? openWebApp;

  @override
  State<_BrowserFallbackPage> createState() => _BrowserFallbackPageState();
}

class _BrowserFallbackPageState extends State<_BrowserFallbackPage> {
  bool _opening = false;
  bool _failed = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _failed = false;
    });
    var opened = false;
    try {
      final action = widget.openWebApp;
      opened =
          await (action != null
                  ? action()
                  : launchUrl(
                      ReleaseRuntimeConfig.resolveWebAppBaseUri(
                        projectId: ReleaseRuntimeConfig.defaultWebProjectId,
                      ),
                      mode: LaunchMode.externalApplication,
                    ))
              .timeout(const Duration(seconds: 20));
    } catch (_) {
      // Configuration and OS launch details are not user-facing diagnostics.
    }
    if (!mounted) return;
    setState(() {
      _opening = false;
      _failed = !opened;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Use RonikCloud in your browser',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Cloud sign-in is not available in this native app on '
                    'your operating system yet. Open the web app to access '
                    'your workspace.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _opening ? null : _open,
                    icon: const Icon(Icons.open_in_browser),
                    label: Text(
                      _opening
                          ? 'Opening browser…'
                          : _failed
                          ? 'Try opening the web app again'
                          : 'Open the web app',
                    ),
                  ),
                  if (_failed) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'The web app could not be opened. Check your browser '
                      'settings and try again.',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
