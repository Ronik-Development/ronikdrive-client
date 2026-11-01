import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'upload_coordinator.dart';
import 'upload_capacity_dialog.dart';

class UploadTransferTray extends StatelessWidget {
  const UploadTransferTray({super.key, this.onReview, this.onCancel});
  final VoidCallback? onReview;
  final VoidCallback? onCancel;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: UploadCoordinator.instance,
    builder: (context, _) {
      final coordinator = UploadCoordinator.instance;
      final jobs = coordinator.jobs;
      final active = jobs
          .where(
            (job) => !const {
              UploadJobState.completed,
              UploadJobState.failed,
              UploadJobState.canceled,
            }.contains(job.state),
          )
          .toList();
      final failed = jobs
          .where((job) => job.state == UploadJobState.failed)
          .length;
      final completed = jobs
          .where((job) => job.state == UploadJobState.completed)
          .length;
      if (active.isEmpty && failed == 0) return const SizedBox.shrink();
      final bytes = active.fold<int>(
        0,
        (sum, job) => sum + job.acknowledgedBytes,
      );
      final total = active.fold<int>(0, (sum, job) => sum + job.totalBytes);
      final speed = active.fold<double>(
        0,
        (sum, job) => sum + job.bytesPerSecond,
      );
      final paused = active.every((job) => job.state == UploadJobState.paused);
      final finalizing =
          active.isNotEmpty &&
          active.every((job) => job.state == UploadJobState.finalizing);
      final eta = speed <= 0 ? null : ((total - bytes) / speed).ceil();
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  active.isEmpty
                      ? 'Uploads need attention'
                      : finalizing
                      ? 'Finishing file details'
                      : paused
                      ? 'Uploads paused'
                      : 'Uploading ${active.length} item(s)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (active.isNotEmpty)
                  LinearProgressIndicator(
                    value: total > 0 ? bytes / total : null,
                    semanticsLabel: 'Upload progress',
                  ),
                const SizedBox(height: 8),
                if (active.isNotEmpty)
                  Text(
                    '${uploadByteLabel(bytes)} of ${uploadByteLabel(total)} accepted'
                    '${speed > 0 ? ' · ${uploadByteLabel(speed.round())}/s' : ''}'
                    '${eta != null ? ' · about $eta seconds left' : ''}',
                  ),
                if (completed > 0) Text('$completed completed'),
                if (failed > 0)
                  Text(
                    '$failed upload(s) need attention. Review saved progress before retrying.',
                  ),
                if (kIsWeb && active.isNotEmpty)
                  const Text(
                    'Keep this browser open. Closing it may pause your uploads.',
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    if (active.isNotEmpty && !finalizing)
                      TextButton.icon(
                        onPressed: paused
                            ? coordinator.resumeAll
                            : coordinator.pauseAll,
                        icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                        label: Text(paused ? 'Resume' : 'Pause'),
                      ),
                    if (active.isNotEmpty && !finalizing)
                      TextButton.icon(
                        onPressed: () {
                          coordinator.cancelAll();
                          onCancel?.call();
                        },
                        icon: const Icon(Icons.close),
                        label: const Text('Cancel uploads'),
                      ),
                    if (failed > 0 && onReview != null)
                      TextButton(
                        onPressed: onReview,
                        child: const Text('Review uploads'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
