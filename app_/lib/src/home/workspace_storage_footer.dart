import 'package:flutter/material.dart';
import '../storage/upload_coordinator.dart';

/// Low-emphasis account information, separate from the working file area.
class WorkspaceStorageFooter extends StatelessWidget {
  const WorkspaceStorageFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text('1 GB included', style: style)),
          TextButton(
            style: TextButton.styleFrom(textStyle: style),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Storage limits'),
                content: const SingleChildScrollView(
                  child: Text(
                    'Your workspace includes 1 GB of storage, with no payment required. '
                    'An individual encrypted file may use your remaining capacity. '
                    '${UploadCoordinator.enabled ? 'Uploads that need more space wait for an upgrade. ' : 'Older upload clients retain a 1 GB authorization allowance per UTC day, including retries. '}'
                    'Try a non-critical file and download it to verify the result. Keep another backup.',
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                ],
              ),
            ),
            child: const Text('Storage limits'),
          ),
        ],
      ),
    );
  }
}
