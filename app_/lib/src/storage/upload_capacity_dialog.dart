import 'package:flutter/material.dart';
import 'upload_coordinator.dart';

enum UploadCapacityAction { upgrade, chooseFewer, manageStorage }

String uploadByteLabel(int bytes) {
  const gib = 1024 * 1024 * 1024;
  if (bytes >= gib) return '${(bytes / gib).toStringAsFixed(2)} GB';
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '$bytes bytes';
}

Future<UploadCapacityAction?> showUploadCapacityDialog(
  BuildContext context,
  UploadCapacityDecision decision,
) => showDialog<UploadCapacityAction>(
  context: context,
  builder: (context) => AlertDialog(
    scrollable: true,
    title: const Text('More space needed'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This upload needs ${uploadByteLabel(decision.selectedBytes)}; you have '
            '${uploadByteLabel(decision.remainingBytes)} left on your '
            '${uploadByteLabel(decision.capacityBytes)} plan.',
          ),
          const SizedBox(height: 16),
          Text(
            'Used: ${uploadByteLabel(decision.usageBytes)}\n'
            'Reserved by other uploads: ${uploadByteLabel(decision.reservedBytes)}\n'
            'Additional space needed: ${uploadByteLabel(decision.shortfallBytes)}',
          ),
          const SizedBox(height: 16),
          const Text(
            'Your selection is waiting. Upgrade to continue uploading these files.',
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () =>
            Navigator.pop(context, UploadCapacityAction.manageStorage),
        child: const Text('Manage storage'),
      ),
      TextButton(
        onPressed: () =>
            Navigator.pop(context, UploadCapacityAction.chooseFewer),
        child: const Text('Choose fewer files'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, UploadCapacityAction.upgrade),
        child: const Text('Upgrade and continue'),
      ),
    ],
  ),
);
