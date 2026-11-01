import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Only fixed event codes and timestamps may cross this boundary. No file
/// names, paths, exception messages, keys or customer content are accepted.
enum ActivityKind {
  backupProblem,
  backgroundLocked,
  backgroundProblem,
  transferInterrupted,
  storageFull,
  restoreFailed,
  restoreVerified,
  securityChanged,
}

extension ActivityKindPresentation on ActivityKind {
  bool get informational =>
      this == ActivityKind.restoreVerified ||
      this == ActivityKind.securityChanged;
  String get title => switch (this) {
    ActivityKind.backupProblem => 'Backup needs attention',
    ActivityKind.backgroundLocked => 'Background backup is paused',
    ActivityKind.backgroundProblem => 'Background backup could not finish',
    ActivityKind.transferInterrupted => 'Transfers need review',
    ActivityKind.storageFull => 'Not enough storage for an upload',
    ActivityKind.restoreFailed => 'Restore check failed',
    ActivityKind.restoreVerified => 'Restore check completed',
    ActivityKind.securityChanged => 'Security settings changed on this device',
  };
  String get guidance => switch (this) {
    ActivityKind.backupProblem =>
      'Review the affected folders, connection and permissions in Backups. Retry after fixing the problem.',
    ActivityKind.backgroundLocked =>
      'Open your encryption settings and unlock this device. Some secure modes require the app to stay open.',
    ActivityKind.backgroundProblem =>
      'Open Backups to review folder access and storage. A later successful background run clears this alert.',
    ActivityKind.transferInterrupted =>
      'Review interrupted transfers in the Data safety center. Recovery actions preserve queued work.',
    ActivityKind.storageFull =>
      'Free space or review your storage plan. You can still download your files.',
    ActivityKind.restoreFailed =>
      'Check your connection and recovery material, then retry in the Data safety center. Do not reset your keys.',
    ActivityKind.restoreVerified =>
      'One file was successfully read back. This does not verify every file or a full-device recovery.',
    ActivityKind.securityChanged =>
      'Review your account security settings. This records a successful change made here, not activity on other devices.',
  };
  String get action => switch (this) {
    ActivityKind.backupProblem ||
    ActivityKind.backgroundProblem => 'Review backups',
    ActivityKind.backgroundLocked => 'Open settings',
    ActivityKind.storageFull => 'Review storage',
    ActivityKind.securityChanged => 'Review security',
    _ => 'Open Data safety center',
  };
}

class ActivityEntry {
  const ActivityEntry(this.kind, this.changedAt, this.resolved);
  final ActivityKind kind;
  final DateTime changedAt;
  final bool resolved;
}

class ActivityPreferences {
  const ActivityPreferences({
    this.problems = false,
    this.summaries = false,
    this.security = false,
    this.quietHours = false,
    this.snoozedUntil,
  });
  final bool problems, summaries, security, quietHours;
  final DateTime? snoozedUntil;
  bool allows(ActivityKind kind, DateTime now) {
    if (snoozedUntil?.isAfter(now) == true) return false;
    if (quietHours && (now.hour >= 22 || now.hour < 8)) return false;
    return kind == ActivityKind.securityChanged
        ? security
        : kind.informational
        ? summaries
        : problems;
  }

  ActivityPreferences copyWith({
    bool? problems,
    bool? summaries,
    bool? security,
    bool? quietHours,
    DateTime? snoozedUntil,
    bool clearSnooze = false,
  }) => ActivityPreferences(
    problems: problems ?? this.problems,
    summaries: summaries ?? this.summaries,
    security: security ?? this.security,
    quietHours: quietHours ?? this.quietHours,
    snoozedUntil: clearSnooze ? null : snoozedUntil ?? this.snoozedUntil,
  );
}

class UserActivityStore {
  UserActivityStore(
    this.preferences, {
    required String uid,
    required String scope,
  }) : account = sha256
           .convert(utf8.encode(jsonEncode([scope, uid])))
           .toString();
  final SharedPreferences preferences;
  final String account;
  static final _changes = StreamController<String>.broadcast();
  static Stream<String> get changes => _changes.stream;
  String get _prefix => 'user_activity_v1:$account:';

  Future<void> reload() => preferences.reload();
  ActivityEntry? entry(ActivityKind kind) {
    final raw = preferences.getString('$_prefix${kind.name}');
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return ActivityEntry(
        kind,
        DateTime.fromMillisecondsSinceEpoch(data['at'] as int),
        data['resolved'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  List<ActivityEntry> get entries => [
    for (final kind in ActivityKind.values)
      if (entry(kind) case final value?) value,
  ]..sort((a, b) => b.changedAt.compareTo(a.changedAt));

  /// One record per event type bounds storage and avoids cross-producer list
  /// replacement. Repeated failures neither grow the inbox nor alert again.
  Future<void> _writes = Future.value();
  Future<bool> record(ActivityKind kind, {bool resolved = false}) {
    final result = _writes.then((_) => _record(kind, resolved: resolved));
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<bool> _record(ActivityKind kind, {required bool resolved}) async {
    await reload();
    final previous = entry(kind);
    if ((!kind.informational && previous?.resolved == resolved) ||
        (previous == null && resolved)) {
      return false;
    }
    await preferences.setString(
      '$_prefix${kind.name}',
      jsonEncode({
        'at': DateTime.now().millisecondsSinceEpoch,
        'resolved': resolved,
      }),
    );
    _changes.add(account);
    return true;
  }

  Future<bool> claimAlert(ActivityKind kind, DateTime now) async {
    await reload();
    if (!settings.allows(kind, now)) return false;
    final key = '${_prefix}alert:${kind.name}';
    final previous = preferences.getInt(key);
    if (previous != null &&
        now.millisecondsSinceEpoch - previous <
            const Duration(minutes: 30).inMilliseconds) {
      return false;
    }
    await preferences.setInt(key, now.millisecondsSinceEpoch);
    return true;
  }

  ActivityPreferences get settings => ActivityPreferences(
    problems: preferences.getBool('${_prefix}problems') ?? false,
    summaries: preferences.getBool('${_prefix}summaries') ?? false,
    security: preferences.getBool('${_prefix}security') ?? false,
    quietHours: preferences.getBool('${_prefix}quiet') ?? false,
    snoozedUntil: DateTime.fromMillisecondsSinceEpoch(
      preferences.getInt('${_prefix}snooze') ?? 0,
    ),
  );
  Future<void> saveSettings(ActivityPreferences value) async {
    await preferences.setBool('${_prefix}problems', value.problems);
    await preferences.setBool('${_prefix}summaries', value.summaries);
    await preferences.setBool('${_prefix}security', value.security);
    await preferences.setBool('${_prefix}quiet', value.quietHours);
    await preferences.setInt(
      '${_prefix}snooze',
      value.snoozedUntil?.millisecondsSinceEpoch ?? 0,
    );
    _changes.add(account);
  }
}
