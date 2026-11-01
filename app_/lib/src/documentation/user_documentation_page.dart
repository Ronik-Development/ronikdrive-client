import 'package:flutter/material.dart';

import '../home/download_page.dart';
import '../legal/legal_documents_page.dart';
import '../shared/app_page_title.dart';
import '../support/support_page.dart';

enum DocumentationTopic {
  startHere('start', 'Start here', Icons.rocket_launch_outlined),
  encryption('encryption', 'Encryption', Icons.enhanced_encryption_outlined),
  storageSync('storage-sync', 'Storage & sync', Icons.sync_outlined),
  sharing('sharing', 'Sharing', Icons.group_outlined),
  accountPrivacy('account-privacy', 'Account & privacy', Icons.shield_outlined),
  platforms('platforms', 'Platforms', Icons.devices_outlined);

  const DocumentationTopic(this.slug, this.label, this.icon);

  final String slug;
  final String label;
  final IconData icon;

  static DocumentationTopic fromSlug(String? slug) {
    return DocumentationTopic.values.firstWhere(
      (topic) => topic.slug == slug,
      orElse: () => DocumentationTopic.startHere,
    );
  }
}

class UserDocumentationPage extends StatelessWidget {
  const UserDocumentationPage({super.key, this.initialTopic});

  final String? initialTopic;

  @override
  Widget build(BuildContext context) {
    final selected = DocumentationTopic.fromSlug(initialTopic);
    return DefaultTabController(
      length: DocumentationTopic.values.length,
      initialIndex: DocumentationTopic.values.indexOf(selected),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('RonikCloud Documentation'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final topic in DocumentationTopic.values)
                Tab(icon: Icon(topic.icon), text: topic.label),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _StartHereTab(
              onOpenDownloads: () => _push(context, const DownloadPage()),
              onOpenSupport: () => _push(context, const SupportPage()),
            ),
            const _EncryptionTab(),
            const _StorageSyncTab(),
            const _SharingTab(),
            _AccountPrivacyTab(
              onOpenLegal: () =>
                  _push(context, const LegalDocumentsIndexPage()),
              onOpenSupport: () => _push(context, const SupportPage()),
            ),
            _PlatformsTab(
              onOpenDownloads: () => _push(context, const DownloadPage()),
              onOpenSupport: () => _push(context, const SupportPage()),
            ),
          ],
        ),
      ),
    ).withAppPageTitle('Documentation | RonikCloud');
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

class _StartHereTab extends StatelessWidget {
  const _StartHereTab({
    required this.onOpenDownloads,
    required this.onOpenSupport,
  });

  final VoidCallback onOpenDownloads;
  final VoidCallback onOpenSupport;

  @override
  Widget build(BuildContext context) {
    return _DocumentationTab(
      title: 'Start using RonikCloud',
      introduction:
          'A practical guide to creating an account, protecting your encryption keys, and keeping files available across your devices.',
      actions: [
        FilledButton.icon(
          onPressed: onOpenDownloads,
          icon: const Icon(Icons.download_outlined),
          label: const Text('Download the app'),
        ),
        OutlinedButton.icon(
          onPressed: onOpenSupport,
          icon: const Icon(Icons.support_agent_outlined),
          label: const Text('Contact support'),
        ),
      ],
      sections: const [
        _DocumentationSection(
          title: '1. Create and protect your account',
          icon: Icons.person_add_alt_outlined,
          body:
              'Register with an email address you control, use a unique password, accept the current legal documents, and enable two-factor authentication from Settings > Account Security.',
          bullets: [
            'Never send a password, encryption passphrase, authentication code, or recovery material to support.',
            'Keep access to your account email because password-reset and security notices use it.',
            'After encryption is unlocked, create an encrypted recovery kit in Settings > Account Security and keep its separate passphrase elsewhere.',
            'On a shared device, sign out when you finish and do not enable biometric sign-in for another person.',
          ],
        ),
        _DocumentationSection(
          title: '2. Choose an encryption mode',
          icon: Icons.lock_outline,
          body:
              'Basic protection derives an encryption key for the signed-in account. Advanced secure mode uses a separate passphrase for secure files and shards. RonikCloud cannot recover an advanced secure-mode passphrase.',
          callout:
              'Before using advanced secure mode, record the passphrase in a trusted password manager. Losing it can permanently make secure files unreadable.',
        ),
        _DocumentationSection(
          title: '3. Upload, organize, and sync',
          icon: Icons.cloud_upload_outlined,
          body:
              'Create folders, upload files, and choose backup folders from the workspace. Encryption happens on the device before protected file content is uploaded.',
          bullets: [
            'Use the upload-bandwidth control if a backup competes with calls, games, or other network traffic.',
            'Pin important files for offline use on supported desktop and mobile platforms.',
            'If local and remote copies both change, RonikCloud reports a conflict instead of silently overwriting either copy.',
          ],
        ),
        _DocumentationSection(
          title: '4. Add another device',
          icon: Icons.devices_other_outlined,
          body:
              'Install RonikCloud from the official download page and sign in with the same account. If the account password changed or the older standard key is unavailable, restore the user-held recovery kit from Settings > Account Security. Advanced secure-mode files still require their separate secure-mode passphrase.',
        ),
      ],
    );
  }
}

class _EncryptionTab extends StatelessWidget {
  const _EncryptionTab();

  @override
  Widget build(BuildContext context) {
    return const _DocumentationTab(
      title: 'Encryption standards and boundaries',
      introduction:
          'This page describes the cryptographic profile implemented by the current RonikCloud client. It is an implementation description, not a claim of formal certification or an independent security audit.',
      standards: [
        _EncryptionStandard(
          purpose: 'File content',
          standard: 'AES-256-CTR with HMAC-SHA-256',
          detail:
              'File bytes are encrypted before storage and authenticated so altered ciphertext is rejected during decryption.',
        ),
        _EncryptionStandard(
          purpose: 'File names',
          standard: 'AES-256-GCM',
          detail:
              'Protected file names use authenticated encryption with a fresh nonce and authentication tag.',
        ),
        _EncryptionStandard(
          purpose: 'Folder labels',
          standard: 'AES-256-GCM',
          detail:
              'New protected folder labels are authenticated and encrypted on the device. Shared Business folders use a random folder key wrapped separately for each authorized member.',
        ),
        _EncryptionStandard(
          purpose: 'Backup integrity tags',
          standard: 'HMAC-SHA-256',
          detail:
              'The raw content digest stays in the local backup cache. Remote comparisons use an account-keyed tag, preventing public or cross-account hash matching.',
        ),
        _EncryptionStandard(
          purpose: 'Key derivation',
          standard: 'PBKDF2-HMAC-SHA-256',
          detail:
              'A 256-bit key is derived using 300,000 iterations and a random per-account salt.',
        ),
        _EncryptionStandard(
          purpose: 'Secure shard identifiers',
          standard: 'HMAC-SHA-256',
          detail:
              'Advanced secure-mode shard tokens are deterministic for the key, object, and shard index without exposing the original object name.',
        ),
        _EncryptionStandard(
          purpose: 'Network transport',
          standard: 'HTTPS/TLS',
          detail:
              'App and browser traffic uses HTTPS. Client-side file encryption remains separate from transport encryption.',
        ),
      ],
      sections: [
        _DocumentationSection(
          title: 'Encrypted object format',
          icon: Icons.data_object_outlined,
          body:
              'Encrypted objects contain the nonce, ciphertext, and authentication code needed for decryption. A nonce is not secret; its uniqueness is what protects repeated encryption under the same key.',
        ),
        _DocumentationSection(
          title: 'Keys on your device',
          icon: Icons.phonelink_lock_outlined,
          body:
              'The app keeps active encryption material in the local session and uses operating-system-backed secure storage where the platform provides it. When a workspace key is locked, file and folder ciphertext is shown only as an Encrypted file, Secure file, or Encrypted folder placeholder. The workspace keeps an explicit unlock card available instead of opening a password prompt just because a background snapshot arrived. Advanced secure-mode passphrases are entered locally and are not stored as recoverable server-side passwords.',
          callout:
              'Shared Business items use keys wrapped for authorized members. They never fall back to the Personal password-derived key path.',
        ),
        _DocumentationSection(
          title: 'User-held encryption recovery',
          icon: Icons.key_outlined,
          body:
              'The Account Security page can export the standard encryption key as an AES-256-GCM recovery kit protected by a separate passphrase. Account identity, environment identity, encryption parameters, and the key are all inside authenticated ciphertext. The kit can restore Personal encrypted data and the wrapped Business encryption identity after recent account authentication.',
          callout:
              'RonikCloud does not upload the kit or its passphrase. Keep them separately. Support cannot recreate a lost kit, recovery passphrase, or advanced secure-mode passphrase.',
        ),
        _DocumentationSection(
          title: 'Private device state',
          icon: Icons.backup_outlined,
          body:
              'Cached Personal and Business file/folder listings, selected backup paths, raw comparison fingerprints, interrupted-transfer checkpoints, multipart upload IDs, and offline file, folder, and directory mappings are kept in an account-scoped AES-256-GCM cache. Its random key is held by the operating system credential store. Cache purpose, Firebase environment, and account identity are authenticated, so copying an entry to another account or cache cannot unlock it. Older plaintext cache entries migrate automatically, tampered entries are discarded safely, and a failed protection attempt removes legacy plaintext instead of leaving it behind.',
          callout:
              'Offline file bodies are also stored in a chunked authenticated vault bound to the environment, account, object, and file key. Secure-mode files still require the secure workspace key. Files handed to another app use an opaque, private temporary copy with automatic expiry and crash cleanup. You can clear RonikCloud handoff copies immediately in Data safety center > Privacy, but the receiving app may retain its own copy or recent-file history.',
        ),
        _DocumentationSection(
          title: 'Metadata that remains necessary',
          icon: Icons.info_outline,
          body:
              'The service still needs operational metadata such as object size, upload timestamps, opaque file and folder references, parent-child and access relationships, encrypted-name fields, keyed backup-integrity tags, storage-routing identifiers, subscription state, and limited security records. A successful open, preview, download, restore, or share sends only the opaque file ID and updates one lifecycle boundary shared by the entire UTC week; the service does not retain the action kind or a precise per-file access time. Legacy precise access fields are removed in bounded maintenance passes. Once a file or folder has a canonical encrypted label and matching recovery metadata, another bounded pass removes redundant readable names and paths. Missing encrypted labels still require an authorized device because the service never receives the decryption key. Company audit history stores fixed action types, timestamps, company-scoped pseudonymous member references, and small policy or aggregate changes. Current member labels are resolved only on an authorized device; audit records do not duplicate emails, names, raw account IDs, workspace labels, or file references and expire after the configured retention period (365 days by default). Client-side encryption cannot hide request timing, IP/connection data, traffic volume, or all account activity from service infrastructure. Older folder records or backup fingerprints can retain legacy metadata until an affected item is migrated or uploaded again.',
        ),
        _DocumentationSection(
          title: 'Your security responsibilities',
          icon: Icons.key_outlined,
          body:
              'Use unique credentials, keep devices updated and locked, verify complete share links before sending them, and keep an offline recovery plan for advanced secure-mode passphrases.',
          callout:
              'RonikCloud support never needs your password, passphrase, private key, one-time authentication code, or full share-link secret.',
        ),
      ],
    );
  }
}

class _StorageSyncTab extends StatelessWidget {
  const _StorageSyncTab();

  @override
  Widget build(BuildContext context) {
    return const _DocumentationTab(
      title: 'Storage, backup, and sync',
      introduction:
          'How protected uploads, folder backup, offline files, bandwidth limits, trash, and version recovery behave.',
      sections: [
        _DocumentationSection(
          title: 'Uploads and folders',
          icon: Icons.folder_copy_outlined,
          body:
              'Uploads are organized in workspace folders. Protected file names, file content, and new folder labels are encrypted on the device before they are stored. Provider object paths and new automatic-backup folder identifiers are opaque rather than name-derived.',
        ),
        _DocumentationSection(
          title: 'Safe file and folder changes',
          icon: Icons.sync_problem_outlined,
          body:
              'If a rename, move, folder change, or recycle action loses its response, RonikCloud does not assume that it failed. The last verified workspace stays visible, repeating workspace changes and uploads is paused, and Refresh files obtains an authoritative server view before work continues.',
          callout:
              'Recovery guidance uses fixed categories. It does not display provider responses, filenames, folder labels, object references, account details, exception messages, or stacks.',
        ),
        _DocumentationSection(
          title: 'Large photos and browser uploads',
          icon: Icons.photo_outlined,
          body:
              'On the web, the file or photo chooser opens directly from your upload action so Safari and other browsers do not block it. After selection, RonikCloud confirms encryption is ready before opening the selected file or reading any bytes. It then reads files in small repeatable slices while encrypting them instead of loading and duplicating the complete selection in memory. For one image within the 24 MiB preview limit, it may retain one bounded source snapshot so the encrypted original and later preview always represent the same bytes. Larger images continue streaming without a preview. Preview decoding begins only after the encrypted original reaches storage, and a preview problem does not fail the original. Stored preview candidates are capped, decoded, and normalized on your device before display; a corrupt or oversized derivative is discarded and rebuilt from the authenticated encrypted original within a separate local memory limit. Automatic retries do not interrupt you with a password prompt. If a protected preview still needs its key, choose Unlock or retry image preview to unlock deliberately and repair it locally. If encrypted bytes arrived but private workspace metadata still needs a safe retry, the upload result says it is waiting for automatic finalization rather than asking you to upload the original again.',
          callout:
              'Keep the tab open while an upload or finalization retry is active. A true upload failure uses fixed recovery guidance and never displays a provider response, file path, account detail, or raw exception.',
        ),
        _DocumentationSection(
          title: 'Automatic backup',
          icon: Icons.backup_outlined,
          body:
              'Windows builds can watch chosen folders and supported release builds can continue through the background worker. Automatic folder backup is unavailable on Android, iOS, and macOS until persistent folder access is supported. Mac users can still select folders for one-time uploads; mobile users can choose individual files or photos. Saved backup configurations remain intact. The separate iOS Photos backup remains available. Image previews are created on the device within strict size and pixel limits from the exact bytes uploaded as the encrypted original. Encrypted preview objects use neutral opaque storage names, and service metadata does not record whether a file has a preview. If a photo changes during capture, is too large, malformed, or unsupported, RonikCloud safely skips the optional preview and continues uploading the encrypted original. Successful backup diagnostics use only fixed events; failures may add a temporary opaque item reference and fixed category instead of filenames, folder labels, absolute paths, byte counts, exception messages, or stacks. Mobile background work is scheduled by the operating system and is not guaranteed to run immediately. Web browsers cannot back up a closed local folder.',
        ),
        _DocumentationSection(
          title: 'iPhone and iPad photos',
          icon: Icons.photo_library_outlined,
          body:
              'Upload > Photos lets you choose images directly from the iOS Photos library without exporting them to Files or granting access to the whole library. Backups > Back up Photos saves original still images you allow access to. Choose limited Photos access for selected images, or full access to include new photos on later scans. Use Manage Photos access to change your selection. Photo backup does not include videos, Live Photo motion, albums, or Photos edit instructions. Deleting a photo on the device does not delete its cloud backup. Photos stored only in iCloud must download before encryption and upload. Temporary exports are removed after use; interrupted exports expire locally. Background timing is controlled by iOS, so open RonikCloud and use Back up now to finish a large backup.',
        ),
        _DocumentationSection(
          title: 'Private provider import recovery',
          icon: Icons.cloud_download_outlined,
          body:
              'When a connected storage provider rejects sign-in, folder browsing, selection, or download, RonikCloud shows fixed recovery guidance instead of its response body, remote path, account address, filename, token, exception, or stack. The import view keeps the current folder and selection so you can retry. Completed RonikCloud uploads remain encrypted; retry only files still missing.',
        ),
        _DocumentationSection(
          title: 'Sync conflicts',
          icon: Icons.sync_problem_outlined,
          body:
              'When the local and remote copy both changed, automatic upload pauses and records a conflict. Review both copies before choosing which version to keep.',
        ),
        _DocumentationSection(
          title: 'Bandwidth presets',
          icon: Icons.speed_outlined,
          body:
              'Upload limits can be unset for maximum available speed, set to a preset, or customized. Limits control RonikCloud upload throughput; other network and provider limits can still reduce actual speed.',
        ),
        _DocumentationSection(
          title: 'Offline files, trash, and rewind',
          icon: Icons.restore_outlined,
          body:
              'Offline pins keep an authenticated encrypted vault copy on supported devices. Use RonikCloud to open it; files sent to another app use an opaque temporary decrypted handoff that expires automatically. Clear RonikCloud handoff copies at any time in Data safety center > Privacy. Existing readable offline copies are upgraded when their encryption key becomes available. Trash and rewind features help recover supported workspace records, but they are not a substitute for an independent backup of irreplaceable data.',
        ),
      ],
    );
  }
}

class _SharingTab extends StatelessWidget {
  const _SharingTab();

  @override
  Widget build(BuildContext context) {
    return const _DocumentationTab(
      title: 'Sharing and collaboration',
      introduction:
          'Share protected copies, request encrypted uploads, and collaborate without exposing more access than necessary.',
      sections: [
        _DocumentationSection(
          title: 'Encrypted share links and email',
          icon: Icons.link_outlined,
          body:
              'RonikCloud creates a separate encrypted share copy for files up to 20 MiB, within the public download transport limit. Regular workspace uploads keep their existing limits. New links protect the filename and content type with the same client-held secret as the file. Password protection is recommended and enabled by default: choose your own password with at least 12 characters or let RonikCloud generate one. You can email this link directly to one recipient; RonikCloud and its email provider process that address and a token-only URL, never the password, private file label, or content key. Email accepted means the provider accepted the message, not that it reached the inbox. Retry reuses the same send identity, and a failed email leaves the link available for manual copying. Send the password separately. If you turn password protection off, a fresh random key lives only in the private URL fragment and an owner-encrypted envelope. Anyone holding the complete link can decrypt the shared copy. Email opens in your own email app, where you review the message and press Send; RonikCloud does not receive that private key. Missing email apps leave Copy link and Retry available. The recipient opens protected metadata locally and chooses Download; loading the page does not automatically retrieve the encrypted file. After opening that small protected envelope, the browser sends a secret-derived proof that the backend checks before encrypted bytes leave storage. A caller without the password or private fragment key therefore cannot consume the link request budget. Every public metadata or download request rechecks that the source is active; for Business files it also rechecks the creator\'s current membership plus share and download permission. Moving the source to the recycle bin or removing that access disables the link. New links default to ten encrypted-payload requests and always keep a budget from 1 to 100. Generic first-access, near-budget, and blocked-proof alerts contain no recipient, filename, token, or file identifier. Direct invalid proofs are throttled by salted token and token/network hashes before encrypted bytes are read. New expiry boundaries are rounded up to the next UTC hour, and new link records retain no exact creation, revocation, update, or access time. Your link dashboard keeps the request count, proof state, revocation, and one-bit alert states. Use Emergency: revoke every link in per-file management or the Data Safety Center to close all active links across Personal and Business files; copies already downloaded cannot be recalled. File cards derive their link badge on your device from links owned by your account; RonikCloud does not copy share state, counts, or an exact last-share time onto the file record. In a Business workspace, other members do not receive your link badge. The encrypted share derivative uses the creator\'s opaque Personal storage prefix so its object key does not encode the company scope; the service still retains the owner and source identifiers required to authorize requests. Older app versions may temporarily write exact lifecycle times; current owner actions and bounded backend maintenance delete them. The link is copied separately; send the password through a different communication channel when possible.',
          bullets: [
            'Revoke links that are no longer needed.',
            'Recreate a link marked Legacy so token-only encrypted download access is removed.',
            'Treat the complete link and any separate password as sensitive data.',
            'Confirm the recipient before sharing confidential information.',
          ],
        ),
        _DocumentationSection(
          title: 'Encrypted file requests',
          icon: Icons.upload_file_outlined,
          body:
              'A file-request link lets another person submit files. The request title, submitted filename, content type, and file body are encrypted on the sender’s device. The encryption key is carried in the private URL fragment, which browsers do not send in the HTTP request, and in a separate owner-encrypted envelope. The public page uses a limited metadata API that does not reveal the owner account; it never reads the request document directly. It shows only the remaining submission slots and an approximate availability boundary derived from the already-public coarse expiry. A sender temporarily reserves one slot while the encrypted upload finishes. An abandoned attempt releases its slot automatically; the page distinguishes that temporary state from a request whose completed-upload limit was reached. A possible encrypted orphan is removed only after a safety delay, and ambiguous storage identity is retained for review rather than risking deletion of another object. New request expiry is rounded up to the next UTC hour, adding less than an hour without shortening the selected duration. Exact creation, close, completion, and submission-status times are not retained. Active requests that expire soon and pending incoming files appear first in the owner view without relying on creation timestamps. Anyone with the complete URL can still use the request until it expires, is revoked, or reaches its limits, so share it through a trusted channel and close it when finished.',
        ),
        _DocumentationSection(
          title: 'Private link recovery',
          icon: Icons.link_off_outlined,
          body:
              'Public file-request and encrypted-share pages never display an API response body or arbitrary exception. Expired links, invalid private keys, upload limits, network interruptions, and unsupported protection use fixed guidance. If protected metadata cannot load, use the visible Retry action. The original upload file remains on the sender’s device when an encrypted upload fails; do not send the complete secret-bearing link to support.',
        ),
        _DocumentationSection(
          title: 'Teams, comments, and reviews',
          icon: Icons.groups_outlined,
          body:
              'Company workspaces use roles and current membership checks for storage actions. Give each person the lowest role they need and remove departed members promptly. To invite someone, select only their role and access areas. RonikCloud asks for no address or name, performs no account lookup, and gives the admin a seven-day one-time code to share privately. Anyone holding that code can claim the selected access while signed in, so verify its fingerprint through a separate trusted channel. Access begins only after the recipient accepts. If a code is lost or sent to the wrong person, use Revoke invitation on its pending row; the code stops working immediately and no active member is removed. A copied code is cleared after two minutes when it is still the unchanged clipboard value and the platform permits the check. Clear it manually after use on platforms that block background clipboard access. Membership, shared-scope, download-permission, or group changes add affected spaces to the protected follow-up banner, including changes made from another administrator device. Open each available space from an authorized trusted device and run Reconcile encrypted member access. Upload-only users do not receive new decryption keys. You can pause safely or close the app: authenticated progress and detailed reminders are encrypted through the device credential store, and Resume skips completed items. RonikCloud synchronizes only required/completed revision counters on the already-known company or group record; it does not receive the reminder reason, member, file, or label. New comment text, review notes, display names, and mention addresses are encrypted on your device with the file key. The service still sees the file/account identifiers, review status, timestamps, and notification routing needed to operate the feature. An original author or reviewer automatically protects their own validated older readable entry when opening it. Other members cannot silently migrate that text; it can remain readable to the provider until the original person opens it or a new protected review replaces it.',
        ),
        _DocumentationSection(
          title: 'Safe Business refresh',
          icon: Icons.sync_lock_outlined,
          body:
              'Refreshing company or administration access keeps the last verified encrypted workspace on screen instead of tearing it down. Personal and assigned-company file and folder updates are tracked independently and merged by opaque record ID, so an update or removal from one source cannot hide a record that remains authorized by the other source. File and folder updates are applied in arrival order. The encrypted device cache retains only the source categories needed to rebuild that split. Company, membership, scope, group, or storage-permission changes immediately clear decrypted Business keys, names, previews, and stale preview work. Losing download permission also removes assigned records and quota contribution from the visible and encrypted local state, rejects late snapshots and downloads, and prevents an in-flight offline copy from being registered. Upload-only and read-only roles receive explicit guidance and only the actions their current server-mirrored permissions allow. A temporary network failure appears in place with Retry and Dismiss, while duplicate refresh actions are disabled. Lower-level provider and encryption failures are reduced to fixed guidance; member IDs, object references, filenames, folder labels, response details, and exception text are not displayed or retained in file/folder diagnostics.',
        ),
        _DocumentationSection(
          title: 'Confirm sensitive Business changes',
          icon: Icons.rule_folder_outlined,
          body:
              'If a member, group, access, or storage-policy request loses its response, the service may already have applied the change. RonikCloud keeps the last verified dashboard visible and disables further administration changes instead of replaying the request. Use Refresh status to load the authoritative result before repeating or starting another change. If refresh also fails, the safety lock remains in place.',
          callout:
              'This recovery notice uses fixed text. It does not display a provider response, member identifier, object reference, filename, or raw exception.',
        ),
        _DocumentationSection(
          title: 'Reliable private Business history',
          icon: Icons.receipt_long_outlined,
          body:
              'The Logs tab distinguishes an unavailable activity query from a verified empty history. If the latest bounded page cannot prove that it contains every retained event, RonikCloud labels it as recent activity and explains that older events may exist. Refresh an unavailable history before relying on it for an access review.',
          callout:
              'Activity titles come from a fixed vocabulary. File and folder names, company and group labels, comments, raw account identifiers, provider errors, and arbitrary server titles are not displayed.',
        ),
        _DocumentationSection(
          title: 'Safe collaboration recovery',
          icon: Icons.refresh_rounded,
          body:
              'A failed collaboration request never copies a provider response, path, token, filename, or account address onto the screen. RonikCloud uses a fixed recovery message instead. A failed live update is shown as unavailable with Retry, not as an empty discussion. If automatic protection of your older comment or review cannot be confirmed, Retry protection reuses the same encrypted payload. For a review, the server also verifies its original reviewer, status, and legacy-content fingerprint before replacing readable fields. Refresh file access, confirm your role with an administrator when needed, and retry without sending encryption material to support.',
        ),
        _DocumentationSection(
          title: 'Content rights',
          icon: Icons.copyright_outlined,
          body:
              'Only upload or share files you own or have permission to store and distribute. Report suspected abuse or accidental disclosure to support@ronikcloud.com.',
        ),
      ],
    );
  }
}

class _AccountPrivacyTab extends StatelessWidget {
  const _AccountPrivacyTab({
    required this.onOpenLegal,
    required this.onOpenSupport,
  });

  final VoidCallback onOpenLegal;
  final VoidCallback onOpenSupport;

  @override
  Widget build(BuildContext context) {
    return _DocumentationTab(
      title: 'Account security and privacy',
      introduction:
          'Manage sign-in protection, sessions, billing, privacy choices, legal documents, and account closure requests.',
      actions: [
        FilledButton.tonalIcon(
          onPressed: onOpenLegal,
          icon: const Icon(Icons.policy_outlined),
          label: const Text('Open legal documents'),
        ),
        OutlinedButton.icon(
          onPressed: onOpenSupport,
          icon: const Icon(Icons.support_agent_outlined),
          label: const Text('Privacy or account help'),
        ),
      ],
      sections: const [
        _DocumentationSection(
          title: 'Sign-in protection',
          icon: Icons.verified_user_outlined,
          body:
              'Use a unique password and enable two-factor authentication. Biometric sign-in is a device convenience layer; it does not replace the account password or encryption passphrase.',
        ),
        _DocumentationSection(
          title: 'Private failure recovery',
          icon: Icons.refresh_rounded,
          body:
              'Sign-in connection, Account Security, recovery-kit, tester-signup, subscription-status, Stripe-management, App Store purchase, and checkout failures use fixed recovery guidance. RonikCloud does not copy exception text, WebView descriptions, portal URLs, API response bodies, account details, transaction details, file paths, or provider details onto these screens. Use the visible Retry action for sign-in connection, security-settings refresh, subscription status, or checkout loading. A failed billing-management action leaves current access unchanged, and an App Store purchase remains available to restore.',
        ),
        _DocumentationSection(
          title: 'Sessions and device hygiene',
          icon: Icons.devices_outlined,
          body:
              'Keep the operating system and RonikCloud updated, lock the device, remove access from devices you no longer control, and sign out on shared computers.',
        ),
        _DocumentationSection(
          title: 'Encryption recovery',
          icon: Icons.key_outlined,
          body:
              'Create or restore a user-held encrypted recovery kit in Settings > Account Security. Creating or restoring requires the current account password and also a two-factor code when 2FA is enabled. The recovery passphrase must differ from the account password.',
          callout:
              'Store the kit file and its recovery passphrase separately. Anyone who obtains both and can sign in to the matching account may unlock its standard encrypted Personal and Business data.',
        ),
        _DocumentationSection(
          title: 'Privacy controls',
          icon: Icons.privacy_tip_outlined,
          body:
              'Your sign-in email and display name remain in Firebase Authentication, where they are required for login, but new general workspace profiles do not duplicate them. General profiles also do not supply readable company labels: Business navigation uses labels decrypted for your authorized session, or neutral protected placeholders. Bounded maintenance removes older company-label mirrors immediately and removes older profile identity copies after any legacy email-derived storage identity is safely migrated. Product-update email is optional. Automatic diagnostics are off by default; if you enable them, RonikCloud receives only fixed error, reason, and library codes, platform, build mode, and fatal state for at most 30 days—not an account ID or Support code, exception message or stack, filename, path, workspace label, URL, or provider object reference. Authentication is used transiently to enforce consent and rate limits. A workspace problem report is separate: it removes common emails, paths, filenames, tokens, and secret-like values on your device, sends no file or automatic diagnostic, and uses an opaque Support code instead of copying your account email or raw account ID. Its remaining text is readable by support and retained for at most 90 days. Privacy, deletion, billing, and ownership-sensitive requests should still come from the account email so ownership can be verified safely.',
        ),
        _DocumentationSection(
          title: 'Request account closure',
          icon: Icons.delete_forever_outlined,
          body:
              'Settings > Account Security records an authenticated account-closure request for support review. Submitting it does not immediately sign you out, end access, cancel billing, or delete data. Cancel renewal separately if desired. Support verifies ownership and confirms the effects before performing permanent closure. Download anything you need first. Some provider, billing, security, audit, or backup records may remain for retention periods described in the legal documents.',
          callout:
              'Completed account closure and losing an advanced secure-mode passphrase can both be irreversible. Review the notice and support confirmation carefully.',
        ),
      ],
    );
  }
}

class _PlatformsTab extends StatelessWidget {
  const _PlatformsTab({
    required this.onOpenDownloads,
    required this.onOpenSupport,
  });

  final VoidCallback onOpenDownloads;
  final VoidCallback onOpenSupport;

  @override
  Widget build(BuildContext context) {
    return _DocumentationTab(
      title: 'Platforms, installation, and support',
      introduction:
          'RonikCloud supports web, Android, iOS, macOS, and Windows. Linux users can use the web app; the native Linux runner does not support cloud sign-in. Availability can differ while a platform is in testing.',
      actions: [
        FilledButton.icon(
          onPressed: onOpenDownloads,
          icon: const Icon(Icons.download_outlined),
          label: const Text('View platform downloads'),
        ),
        OutlinedButton.icon(
          onPressed: onOpenSupport,
          icon: const Icon(Icons.support_agent_outlined),
          label: const Text('Get help'),
        ),
      ],
      sections: const [
        _DocumentationSection(
          title: 'Web',
          icon: Icons.language_outlined,
          body:
              'The web app provides quick access without installation. Browser security and file-system restrictions mean closed-app folder backup and some native integrations are unavailable.',
        ),
        _DocumentationSection(
          title: 'Android, iOS, and macOS',
          icon: Icons.mobile_friendly_outlined,
          body:
              'Mobile and Apple builds may be distributed through Google Play testing or Apple TestFlight until their public-store releases are approved. Install only from the official RonikCloud download page or a verified store invitation.',
        ),
        _DocumentationSection(
          title: 'Windows and Linux',
          icon: Icons.desktop_windows_outlined,
          body:
              'Desktop archives are published through the official download page. Verify the release source, extract or install it in a trusted location, and allow the background worker only if you want automatic folder backup.',
        ),
        _DocumentationSection(
          title: 'When requesting support',
          icon: Icons.support_agent_outlined,
          body:
              'Include the account email, platform, app version, approximate time, and non-sensitive error text. Never include passwords, passphrases, authentication codes, private keys, payment-card data, or complete secret-bearing share links.',
        ),
      ],
    );
  }
}

class _DocumentationTab extends StatelessWidget {
  const _DocumentationTab({
    required this.title,
    required this.introduction,
    this.sections = const [],
    this.standards = const [],
    this.actions = const [],
  });

  final String title;
  final String introduction;
  final List<_DocumentationSection> sections;
  final List<_EncryptionStandard> standards;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: ListView(
          key: PageStorageKey<String>(title),
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 56),
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: 0.32),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      introduction,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                    ),
                    if (actions.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Wrap(spacing: 10, runSpacing: 10, children: actions),
                    ],
                  ],
                ),
              ),
            ),
            if (standards.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                'Current implementation profile',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              for (final standard in standards) ...[
                _EncryptionStandardCard(standard: standard),
                const SizedBox(height: 10),
              ],
            ],
            for (final section in sections) ...[
              const SizedBox(height: 14),
              _DocumentationSectionCard(section: section),
            ],
          ],
        ),
      ),
    );
  }
}

class _DocumentationSection {
  const _DocumentationSection({
    required this.title,
    required this.icon,
    required this.body,
    this.bullets = const [],
    this.callout,
  });

  final String title;
  final IconData icon;
  final String body;
  final List<String> bullets;
  final String? callout;
}

class _DocumentationSectionCard extends StatelessWidget {
  const _DocumentationSectionCard({required this.section});

  final _DocumentationSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(section.icon, color: colors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    section.title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              section.body,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
            ),
            for (final bullet in section.bullets)
              Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Icon(Icons.circle, size: 6, color: colors.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        bullet,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (section.callout != null) ...[
              const SizedBox(height: 14),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.tertiaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: colors.onTertiaryContainer,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          section.callout!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.5,
                            color: colors.onTertiaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EncryptionStandard {
  const _EncryptionStandard({
    required this.purpose,
    required this.standard,
    required this.detail,
  });

  final String purpose;
  final String standard;
  final String detail;
}

class _EncryptionStandardCard extends StatelessWidget {
  const _EncryptionStandardCard({required this.standard});

  final _EncryptionStandard standard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: Text(
                standard.purpose,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    standard.standard,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    standard.detail,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
