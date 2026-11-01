import 'package:flutter/material.dart';

class EncryptionRecoveryPanel extends StatelessWidget {
  const EncryptionRecoveryPanel({
    super.key,
    required this.busy,
    required this.onCreate,
    required this.onRestore,
  });

  final bool busy;
  final VoidCallback onCreate;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.key_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Encryption recovery kit',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Protect access to older encrypted Personal files and your Business encryption identity after a password reset or on a new device.',
            ),
            const SizedBox(height: 8),
            const Text(
              'The kit is encrypted with a separate recovery passphrase. RonikCloud does not upload the kit or the passphrase; keep them separately in places you control.',
            ),
            if (busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: busy ? null : onCreate,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Create recovery kit'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onRestore,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Restore from kit'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
