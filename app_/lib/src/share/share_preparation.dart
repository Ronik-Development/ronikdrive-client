import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Shows preparation stages while allowing the user to keep browsing.
Future<T> runSharePreparation<T>({
  required BuildContext context,
  required String initialStatus,
  required Future<T> Function(ValueChanged<String> updateStatus) prepare,
}) async {
  final status = ValueNotifier(initialStatus);
  final navigator = Navigator.of(context);
  final route = DialogRoute<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Preparing share'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: 20),
          ValueListenableBuilder<String>(
            valueListenable: status,
            builder: (context, value, _) =>
                Semantics(liveRegion: true, child: Text(value)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Continue browsing'),
        ),
      ],
    ),
  );
  unawaited(navigator.push(route));
  try {
    // Paint feedback before starting encryption or network work.
    await SchedulerBinding.instance.endOfFrame;
    return await prepare((value) => status.value = value);
  } finally {
    if (route.isActive) navigator.removeRoute(route);
    await route.completed;
    status.dispose();
  }
}
