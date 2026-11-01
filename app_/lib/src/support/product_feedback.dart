import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/app_page_title.dart';

class FeedbackPromptPreferences {
  FeedbackPromptPreferences(String accountScope)
    : key = 'product-feedback-v1-${sha256.convert(utf8.encode(accountScope))}';

  final String key;
  static const interval = Duration(days: 30);

  bool isDue(SharedPreferences prefs, DateTime now) {
    if (prefs.getBool('$key-disabled') == true) return false;
    final last = prefs.getInt('$key-shown');
    return last == null ||
        now.millisecondsSinceEpoch - last >= interval.inMilliseconds;
  }

  Future<void> postpone(SharedPreferences prefs, DateTime now) async {
    await prefs.setInt('$key-shown', now.millisecondsSinceEpoch);
  }
}

/// An inline invitation, so opening the app never interrupts a file operation.
class ProductFeedbackPrompt extends StatefulWidget {
  const ProductFeedbackPrompt({
    super.key,
    required this.accountScope,
    required this.enabled,
    required this.onOpen,
  });

  final String accountScope;
  final bool enabled;
  final VoidCallback onOpen;

  @override
  State<ProductFeedbackPrompt> createState() => _ProductFeedbackPromptState();
}

class _ProductFeedbackPromptState extends State<ProductFeedbackPrompt> {
  SharedPreferences? _prefs;
  late final _policy = FeedbackPromptPreferences(widget.accountScope);
  bool _visible = false;
  bool _recorded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _visible = _policy.isDue(prefs, DateTime.now());
      });
    } catch (_) {
      // Without durable preferences, avoid showing a prompt every launch.
    }
  }

  Future<void> _remember({bool disable = false}) async {
    try {
      final prefs = _prefs;
      if (prefs == null) return;
      await _policy.postpone(prefs, DateTime.now());
      if (disable) await prefs.setBool('${_policy.key}-disabled', true);
    } catch (_) {
      // A preference failure must not interrupt the workspace.
    }
  }

  void _dismiss({bool disable = false}) {
    setState(() => _visible = false);
    _remember(disable: disable);
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible || !widget.enabled) return const SizedBox.shrink();
    if (!_recorded) {
      _recorded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _remember();
      });
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What would make RonikCloud better for you?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Tell us which features you would like and what bothers you most. Everyone can share feedback.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: widget.onOpen,
                  child: const Text('Share feedback'),
                ),
                TextButton(onPressed: _dismiss, child: const Text('Not now')),
                TextButton(
                  onPressed: () => _dismiss(disable: true),
                  child: const Text('Don’t ask again'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ProductFeedbackPage extends StatefulWidget {
  const ProductFeedbackPage({super.key, required this.onSubmit});

  final Future<void> Function(String description) onSubmit;

  @override
  State<ProductFeedbackPage> createState() => _ProductFeedbackPageState();
}

class _ProductFeedbackPageState extends State<ProductFeedbackPage> {
  final _features = TextEditingController();
  final _frustrations = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _features.dispose();
    _frustrations.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final features = _features.text.trim();
    final frustrations = _frustrations.text.trim();
    if (features.isEmpty && frustrations.isEmpty) {
      setState(() => _error = 'Answer at least one question before sending.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        [
          if (features.isNotEmpty) 'Features I would like:\n$features',
          if (frustrations.isNotEmpty) 'What bothers me most:\n$frustrations',
        ].join('\n\n'),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error =
            'Your feedback could not be sent. Your answers are still here. Check your connection and try again later.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_sending,
      child: Scaffold(
        appBar: AppBar(title: const Text('Share feedback')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Help shape RonikCloud',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'A feature idea, a daily annoyance, or both. Answer whichever question matters to you. No paid plan needed.',
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _features,
                  enabled: !_sending,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 1800,
                  decoration: InputDecoration(
                    labelText: 'What features would you like?',
                    hintStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    hintText:
                        'What would you like to do that you cannot do today?',
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _frustrations,
                  enabled: !_sending,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 1800,
                  decoration: InputDecoration(
                    labelText: 'What bothers you most?',
                    hintStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    hintText:
                        'What feels confusing, slow, or harder than it should?',
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Your answers are readable by the RonikCloud team and kept for up to 90 days. Common private details are filtered before sending; no files or logs are attached. Please leave out passwords and other secrets.',
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _sending ? null : _submit,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_outlined),
                    label: Text(_sending ? 'Sending…' : 'Send feedback'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ).withAppPageTitle('Share feedback | RonikCloud'),
    );
  }
}
