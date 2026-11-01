import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../shared/webview_support.dart';

/// Displays an OAuth authorization page and resolves once the redirect URI is hit.
class OAuthWebViewPage extends StatefulWidget {
  const OAuthWebViewPage({
    super.key,
    required this.authorizationUri,
    required this.redirectUri,
    this.title,
  });

  final Uri authorizationUri;
  final Uri redirectUri;
  final String? title;

  @override
  State<OAuthWebViewPage> createState() => _OAuthWebViewPageState();
}

class _OAuthWebViewPageState extends State<OAuthWebViewPage> {
  WebViewController? _controller;
  bool _loading = true;
  bool _webViewAvailable = false;
  final TextEditingController _redirectController = TextEditingController();
  String? _manualError;
  bool _manualSubmitting = false;

  @override
  void initState() {
    super.initState();
    _webViewAvailable = ensureWebViewPlatformRegistered();
    if (_webViewAvailable) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.transparent)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) {
              if (_matchesRedirect(request.url)) {
                Navigator.of(context).pop(Uri.parse(request.url));
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
            onPageFinished: (_) {
              if (mounted) {
                setState(() => _loading = false);
              }
            },
          ),
        )
        ..loadRequest(widget.authorizationUri);
    } else {
      _loading = false;
    }
  }

  bool _matchesRedirect(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed == null) {
      return false;
    }
    final expected = widget.redirectUri;
    return parsed.scheme.toLowerCase() == expected.scheme.toLowerCase() &&
        parsed.host.toLowerCase() == expected.host.toLowerCase() &&
        parsed.port == expected.port &&
        parsed.path == expected.path;
  }

  @override
  void dispose() {
    _redirectController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_webViewAvailable) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title ?? 'Connect account')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'In-app browser unavailable',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                'This platform doesn\'t provide an embedded web view. '
                'Open the following link in your browser to continue the '
                'sign-in process. After you grant access, the page may show '
                'a 404 error - this is expected. Copy the full address from your '
                'browser\'s address bar and paste it below to finish connecting.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              SelectableText(
                widget.authorizationUri.toString(),
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 24),
              Text(
                'Paste redirected address',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _redirectController,
                enabled: !_manualSubmitting,
                decoration: InputDecoration(
                  hintText: widget.redirectUri.toString(),
                  errorText: _manualError,
                ),
                minLines: 1,
                maxLines: 3,
              ),
              const Spacer(),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _manualSubmitting
                      ? null
                      : () async {
                          await _submitManualRedirect(context);
                        },
                  child: _manualSubmitting
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Complete sign-in'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final controller = _controller!;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? 'Connect account')),
      body: Stack(
        children: [
          WebViewWidget(controller: controller),
          if (_loading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  Future<void> _submitManualRedirect(BuildContext context) async {
    final rawValue = _redirectController.text.trim();
    if (rawValue.isEmpty) {
      setState(() {
        _manualError = 'Paste the full redirect URL from your browser.';
      });
      return;
    }

    Uri? parsed;
    try {
      parsed = Uri.parse(rawValue);
    } on FormatException {
      setState(() {
        _manualError = 'That value is not a valid URL.';
      });
      return;
    }

    if (!_matchesRedirect(parsed.toString())) {
      setState(() {
        _manualError = 'This URL does not match the expected redirect address.';
      });
      return;
    }

    setState(() {
      _manualSubmitting = true;
      _manualError = null;
    });

    Navigator.of(context).pop(parsed);
  }
}
