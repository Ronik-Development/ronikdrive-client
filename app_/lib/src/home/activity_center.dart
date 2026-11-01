import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../shared/notification_service.dart';
import '../shared/user_activity.dart';

/// A local account-scoped inbox. Entries contain fixed messages only.
class ActivityCenterPage extends StatefulWidget {
  const ActivityCenterPage({
    super.key,
    required this.store,
    required this.isCurrentAccount,
  });
  final UserActivityStore store;
  final bool Function() isCurrentAccount;
  @override
  State<ActivityCenterPage> createState() => _ActivityCenterPageState();
}

class _ActivityCenterPageState extends State<ActivityCenterPage>
    with WidgetsBindingObserver {
  StreamSubscription<String>? _subscription;
  bool _busy = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = UserActivityStore.changes
        .where((account) => account == widget.store.account)
        .listen((_) => _reload());
    unawaited(_reload());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      await widget.store.reload();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Activity could not be refreshed. Try again.',
        );
      }
    }
  }

  Future<void> _save(
    ActivityPreferences settings, {
    bool enabling = false,
  }) async {
    if (_busy || !widget.isCurrentAccount()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      bool? permission;
      if (enabling) {
        permission = await NotificationService().requestPermission();
      }
      if (!mounted || !widget.isCurrentAccount()) return;
      await widget.store.saveSettings(settings);
      if (!settings.problems && !settings.summaries && !settings.security) {
        await NotificationService().cancelAccount(widget.store);
      }
      if (mounted && enabling) {
        setState(
          () => _message = permission == false
              ? 'System alerts are unavailable or permission was denied. Updates remain here. You can review permissions in system settings.'
              : 'Preference saved. Your system notification settings also control delivery.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Could not save preferences. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isCurrentAccount()) {
      return Scaffold(
        appBar: AppBar(title: const Text('Activity')),
        body: const Center(
          child: Text(
            'Sign in to the original account to review this activity.',
          ),
        ),
      );
    }
    final settings = widget.store.settings;
    final entries = widget.store.entries;
    final attention = entries
        .where((entry) => !entry.resolved && !entry.kind.informational)
        .toList();
    final recent = entries
        .where((entry) => entry.resolved || entry.kind.informational)
        .toList();
    Widget entryTile(ActivityEntry entry) => ListTile(
      isThreeLine: true,
      leading: Icon(
        entry.resolved
            ? Icons.check_circle_outline
            : entry.kind.informational
            ? Icons.info_outline
            : Icons.error_outline,
      ),
      title: Text('${entry.kind.title}${entry.resolved ? ' — resolved' : ''}'),
      subtitle: Text(
        '${entry.kind.guidance}\n${MaterialLocalizations.of(context).formatMediumDate(entry.changedAt.toLocal())} · ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(entry.changedAt.toLocal()))}',
      ),
      onTap: () {
        if (widget.isCurrentAccount()) Navigator.pop(context, entry.kind);
      },
      trailing: Tooltip(
        message: entry.kind.action,
        child: const Icon(Icons.chevron_right),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity and notifications'),
        actions: [
          IconButton(
            tooltip: 'Refresh activity',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Needs attention',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (attention.isEmpty)
                const ListTile(
                  title: Text('No recorded problems'),
                  subtitle: Text(
                    'This is a history of reported events, not proof that every file is backed up. Check backup and restore status in the Data safety center.',
                  ),
                ),
              ...attention.map(entryTile),
              if (recent.isNotEmpty) ...[
                const Divider(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Recent activity',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                ...recent.map(entryTile),
              ],
              const Divider(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'System notifications',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Optional alerts on this device. System notifications never include file names or content. The in-app history stays available when alerts are off. Delivery while the app is closed depends on platform background support.',
                ),
              ),
              if (kIsWeb)
                const ListTile(
                  title: Text('Web uses the in-app activity center'),
                  subtitle: Text(
                    'System notifications are available in supported desktop and mobile apps.',
                  ),
                ),
              SwitchListTile(
                title: const Text('Problems needing attention'),
                subtitle: const Text(
                  'Backup failures, interrupted transfers and full storage.',
                ),
                value: settings.problems,
                onChanged: _busy || kIsWeb
                    ? null
                    : (value) => _save(
                        settings.copyWith(problems: value),
                        enabling: value,
                      ),
              ),
              SwitchListTile(
                title: const Text('Restore check updates'),
                subtitle: const Text(
                  'An update after a successful restore check. No per-file upload alerts.',
                ),
                value: settings.summaries,
                onChanged: _busy || kIsWeb
                    ? null
                    : (value) => _save(
                        settings.copyWith(summaries: value),
                        enabling: value,
                      ),
              ),
              SwitchListTile(
                title: const Text('Security changes on this device'),
                subtitle: const Text(
                  'Verified changes made here; does not monitor sign-ins elsewhere.',
                ),
                value: settings.security,
                onChanged: _busy || kIsWeb
                    ? null
                    : (value) => _save(
                        settings.copyWith(security: value),
                        enabling: value,
                      ),
              ),
              SwitchListTile(
                title: const Text('Quiet hours'),
                subtitle: const Text(
                  'Silence system alerts from 22:00 to 08:00, device local time. Updates remain here.',
                ),
                value: settings.quietHours,
                onChanged: _busy || kIsWeb
                    ? null
                    : (value) => _save(settings.copyWith(quietHours: value)),
              ),
              ListTile(
                title: Text(
                  settings.snoozedUntil?.isAfter(DateTime.now()) == true
                      ? 'System alerts snoozed'
                      : 'Snooze system alerts',
                ),
                subtitle: const Text(
                  'Silence all categories for one hour. No delayed notification burst.',
                ),
                trailing: TextButton(
                  onPressed: _busy || kIsWeb
                      ? null
                      : () => _save(
                          settings.snoozedUntil?.isAfter(DateTime.now()) == true
                              ? settings.copyWith(clearSnooze: true)
                              : settings.copyWith(
                                  snoozedUntil: DateTime.now().add(
                                    const Duration(hours: 1),
                                  ),
                                ),
                        ),
                  child: Text(
                    settings.snoozedUntil?.isAfter(DateTime.now()) == true
                        ? 'Resume'
                        : 'Snooze',
                  ),
                ),
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Semantics(liveRegion: true, child: Text(_message!)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
