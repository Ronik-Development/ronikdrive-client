import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as windows_webview;

import '../shared/webview_support.dart';
import '../shared/app_page_title.dart';
import '../shared/user_facing_client_failure.dart';

enum CheckoutResult { success, cancelled, dismissed }

class CheckoutWebViewPage extends StatefulWidget {
  const CheckoutWebViewPage({
    super.key,
    required this.checkoutUri,
    required this.successPathSuffixes,
    required this.cancelPathSuffixes,
  });

  final Uri checkoutUri;
  final List<String> successPathSuffixes;
  final List<String> cancelPathSuffixes;

  @override
  State<CheckoutWebViewPage> createState() => _CheckoutWebViewPageState();
}

class _CheckoutWebViewPageState extends State<CheckoutWebViewPage> {
  WebViewController? _controller;
  windows_webview.WebviewController? _windowsController;
  StreamSubscription<String>? _windowsUrlSubscription;
  StreamSubscription<windows_webview.WebErrorStatus>? _windowsErrorSubscription;
  bool _isLoading = true;
  bool _isClosing = false;
  bool _loadFailed = false;
  bool _windowsLoadFailed = false;
  bool _webViewAvailable = false;

  bool get _isWindowsCheckout =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    if (_isWindowsCheckout) {
      unawaited(_initializeWindowsCheckout());
      return;
    }

    unawaited(_initializeCheckout());
  }

  Future<void> _initializeCheckout() async {
    _webViewAvailable = ensureWebViewPlatformRegistered();
    if (!_webViewAvailable) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final controller = WebViewController();
      _controller = controller;
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setBackgroundColor(Colors.transparent);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _loadFailed = false;
              });
            }
          },
          onPageFinished: (_) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
          onWebResourceError: (error) {
            // A failed image, analytics request, or child frame must not
            // replace a working checkout page with a whole-page error.
            if (error.isForMainFrame == false) return;
            if (mounted) {
              setState(() {
                _loadFailed = true;
                _isLoading = false;
              });
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri != null && _isTerminalCheckoutUri(uri)) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onUrlChange: (change) {
            final url = change.url;
            if (url == null) {
              return;
            }
            final uri = Uri.tryParse(url);
            if (uri == null) {
              return;
            }
            _isTerminalCheckoutUri(uri);
          },
        ),
      );
      if (!mounted) return;
      await controller.loadRequest(widget.checkoutUri);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _webViewAvailable = _controller != null;
        _loadFailed = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _initializeWindowsCheckout() async {
    final controller = windows_webview.WebviewController();
    try {
      await controller.initialize();
      await controller.setPopupWindowPolicy(
        windows_webview.WebviewPopupWindowPolicy.deny,
      );
      await controller.setBackgroundColor(Colors.white);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      _windowsUrlSubscription = controller.url.listen((url) {
        if (mounted && _isLoading) {
          setState(() {
            _isLoading = false;
          });
        }
        final uri = Uri.tryParse(url);
        if (uri == null) {
          return;
        }
        _isTerminalCheckoutUri(uri);
      });
      _windowsErrorSubscription = controller.onLoadError.listen((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _windowsLoadFailed = true;
          _isLoading = false;
        });
      });

      await controller.loadUrl(widget.checkoutUri.toString());
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _windowsController = controller;
        _webViewAvailable = true;
        _windowsLoadFailed = false;
        _isLoading = false;
      });
    } catch (_) {
      await controller.dispose();
      if (!mounted) {
        return;
      }
      setState(() {
        _webViewAvailable = false;
        _windowsController = null;
        _isLoading = false;
        _windowsLoadFailed = true;
      });
    }
  }

  Future<void> _retryCheckout() async {
    if (_isLoading || _isClosing) {
      return;
    }
    setState(() {
      _isLoading = true;
      _loadFailed = false;
      _windowsLoadFailed = false;
    });

    if (_isWindowsCheckout) {
      final controller = _windowsController;
      if (controller == null) {
        await _initializeWindowsCheckout();
        return;
      }
      try {
        await controller.loadUrl(widget.checkoutUri.toString());
      } catch (_) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _windowsLoadFailed = true;
          });
        }
      }
      return;
    }

    await _initializeCheckout();
  }

  bool _matchesSuffix(Uri uri, List<String> suffixes) {
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    final trimmedPath = path.startsWith('/') ? path.substring(1) : path;
    final lastPathSegment = uri.pathSegments.isEmpty
        ? ''
        : uri.pathSegments.last.toLowerCase();

    for (final suffix in suffixes) {
      final normalized = suffix.trim().toLowerCase();
      if (normalized.isEmpty) {
        continue;
      }

      // Allow exact scheme://host style markers for custom deep links.
      if (normalized.contains('://')) {
        final marker = Uri.tryParse(normalized);
        if (marker != null) {
          final markerHost = marker.host.toLowerCase();
          final markerPath = marker.path.toLowerCase();
          final schemeMatches =
              marker.scheme.isEmpty || marker.scheme.toLowerCase() == scheme;
          final hostMatches = markerHost.isEmpty || markerHost == host;
          final pathMatches = markerPath.isEmpty || path.endsWith(markerPath);
          if (schemeMatches && hostMatches && pathMatches) {
            return true;
          }
        }
        continue;
      }

      final marker = normalized.startsWith('/')
          ? normalized.substring(1)
          : normalized;
      if (marker.isEmpty) {
        continue;
      }

      // Match deep-link hosts like ronikdrive://payment-success.
      if (host == marker) {
        return true;
      }

      // Match real navigation paths only (never query/body values).
      if (trimmedPath == marker ||
          trimmedPath.endsWith('/$marker') ||
          path.endsWith('/$marker') ||
          lastPathSegment == marker) {
        return true;
      }
    }
    return false;
  }

  bool _isTerminalCheckoutUri(Uri uri) {
    if (_matchesSuffix(uri, widget.successPathSuffixes)) {
      _closeWithResult(CheckoutResult.success);
      return true;
    }
    if (_matchesSuffix(uri, widget.cancelPathSuffixes)) {
      _closeWithResult(CheckoutResult.cancelled);
      return true;
    }
    return false;
  }

  void _closeWithResult(CheckoutResult result) {
    if (_isClosing || !mounted) {
      return;
    }
    _isClosing = true;
    Navigator.of(context).pop(result);
  }

  @override
  void dispose() {
    _windowsUrlSubscription?.cancel();
    _windowsErrorSubscription?.cancel();
    final windowsController = _windowsController;
    if (windowsController != null) {
      unawaited(windowsController.dispose());
    }
    super.dispose();
  }

  Widget _buildUnavailableBody(ThemeData theme, {bool canRetry = false}) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Embedded checkout is unavailable on this platform.',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text(
            'Use a device that supports embedded WebView checkout to complete your subscription.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text(
            userFacingClientFailureMessage(
              UserFacingClientFailure.checkoutLoad,
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          if (canRetry) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => unawaited(_retryCheckout()),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_isWindowsCheckout) {
      final windowsController = _windowsController;
      if (windowsController == null) {
        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: const Text('Stripe checkout'),
            actions: [
              IconButton(
                onPressed: () => _closeWithResult(CheckoutResult.dismissed),
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Close',
              ),
            ],
          ),
          body: _isLoading && !_windowsLoadFailed
              ? const Center(child: CircularProgressIndicator())
              : _buildUnavailableBody(theme, canRetry: true),
        ).withAppPageTitle('Secure Checkout | RonikCloud');
      }

      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Stripe checkout'),
          actions: [
            IconButton(
              onPressed: () => _closeWithResult(CheckoutResult.dismissed),
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Close',
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(3),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _isLoading ? 1 : 0,
              child: _isLoading
                  ? const LinearProgressIndicator(minHeight: 3)
                  : const SizedBox(height: 3),
            ),
          ),
        ),
        body: Column(
          children: [
            if (_windowsLoadFailed)
              Material(
                color: theme.colorScheme.error.withValues(alpha: 0.08),
                child: ListTile(
                  leading: Icon(
                    Icons.error_outline,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(
                    'Checkout page failed to load',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  subtitle: Text(
                    userFacingClientFailureMessage(
                      UserFacingClientFailure.checkoutLoad,
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: () => unawaited(_retryCheckout()),
                    child: const Text('Retry'),
                  ),
                ),
              ),
            Expanded(child: windows_webview.Webview(windowsController)),
          ],
        ),
      ).withAppPageTitle('Secure Checkout | RonikCloud');
    }

    if (!_webViewAvailable) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Stripe checkout'),
          actions: [
            IconButton(
              onPressed: () => _closeWithResult(CheckoutResult.dismissed),
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Close',
            ),
          ],
        ),
        body: _buildUnavailableBody(theme, canRetry: _loadFailed),
      ).withAppPageTitle('Secure Checkout | RonikCloud');
    }

    final controller = _controller!;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Stripe checkout'),
        actions: [
          IconButton(
            onPressed: () => _closeWithResult(CheckoutResult.dismissed),
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Close',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _isLoading ? 1 : 0,
            child: _isLoading
                ? const LinearProgressIndicator(minHeight: 3)
                : const SizedBox(height: 3),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_loadFailed)
            Material(
              color: theme.colorScheme.error.withValues(alpha: 0.08),
              child: ListTile(
                leading: Icon(
                  Icons.error_outline,
                  color: theme.colorScheme.error,
                ),
                title: Text(
                  'Checkout page failed to load',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                subtitle: Text(
                  userFacingClientFailureMessage(
                    UserFacingClientFailure.checkoutLoad,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                trailing: TextButton(
                  onPressed: () => unawaited(_retryCheckout()),
                  child: const Text('Retry'),
                ),
              ),
            ),
          Expanded(child: WebViewWidget(controller: controller)),
        ],
      ),
    ).withAppPageTitle('Secure Checkout | RonikCloud');
  }
}
