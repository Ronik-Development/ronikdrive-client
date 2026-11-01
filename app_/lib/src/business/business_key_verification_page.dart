import '../security/business_encryption_registry.dart';
import '../security/business_encryption_service.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../authentication/login_password_vault.dart';
import '../security/business_recipient_trust.dart';
import '../security/business_recipient_trust_runtime.dart';
import '../security/encryption_recovery_kit.dart';

class BusinessKeyVerificationPage extends StatefulWidget {
  const BusinessKeyVerificationPage({
    super.key,
    required this.auth,
    required this.companyId,
  }) : testState = null;
  @visibleForTesting
  const BusinessKeyVerificationPage.forTesting({
    super.key,
    required this.auth,
    required this.companyId,
    required Map<String, Object?> state,
  }) : testState = state;
  final Map<String, Object?>? testState;
  final FirebaseAuth auth;
  final String companyId;
  @override
  State<BusinessKeyVerificationPage> createState() =>
      _BusinessKeyVerificationPageState();
}

class _BusinessKeyVerificationPageState
    extends State<BusinessKeyVerificationPage> {
  Map<String, Object?>? _state;
  final _approved = <String, Map<String, Object?>>{};
  String? _message;
  bool _busy = false;
  bool _approvalVerified = false;
  late final String? _uid = widget.auth.currentUser?.uid;
  bool get _current =>
      mounted && _uid != null && widget.auth.currentUser?.uid == _uid;
  @override
  void initState() {
    super.initState();
    if (widget.testState != null) {
      _state = widget.testState;
    } else {
      unawaited(_run(_load));
    }
  }

  Future<Map<String, Object?>> _call(
    String name, [
    Map<String, Object?>? data,
  ]) async {
    if (!_current) throw const RecipientTrustException('The account changed.');
    final company = widget.companyId;
    final result =
        await FirebaseFunctions.instanceFor(
              app: widget.auth.app,
              region: 'europe-west1',
            )
            .httpsCallable(name)
            .call<Object?>(data)
            .timeout(const Duration(seconds: 30));
    if (!_current) throw const RecipientTrustException('The account changed.');
    final response = Map<String, Object?>.from(result.data as Map);
    if (widget.companyId != company ||
        (name == 'getBusinessRecipientTrust' &&
            response['companyId'] != company)) {
      throw const RecipientTrustException(
        'Company membership changed. Open verification again.',
      );
    }
    return response;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || !_current) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on RecipientTrustException catch (e) {
      if (_current) setState(() => _message = e.message);
    } catch (_) {
      if (_current) {
        setState(
          () => _message =
              'Company verification could not finish. Refresh status before retrying. Existing files and keys are unchanged.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    final state = await _call('getBusinessRecipientTrust');
    if (state['companyId'] != widget.companyId) {
      throw const RecipientTrustException('The company changed.');
    }
    state['ownIdentity'] = null;
    try {
      final own = await BusinessEncryptionRegistry.forApp(
        widget.auth.app,
      ).getIdentity();
      if (own != null) {
        await BusinessEncryptionService().validateIdentity(
          identity: own,
          accountProtectionKey: await _accountKey(),
        );
        state['ownIdentity'] = own.toMap();
      }
    } on Object {
      /* Never display an unauthenticated backend public key as ours. */
    }
    _approved.clear();
    final raw = state['recipientTrust'];
    var verified = false;
    if (raw != null) {
      final approval = BusinessRecipientApproval.fromMap(
        Map<String, Object?>.from(raw as Map),
      );
      await approval.verify();
      final trust = await BusinessRecipientTrustRuntime.forApp(widget.auth.app);
      try {
        await trust.verifyRecipients(
          companyId: widget.companyId,
          scope: 'metadata:company',
          policy: raw,
          recipients: [],
        );
        verified = true;
        for (final m in approval.members) {
          _approved[m['uid'] as String] = m;
        }
      } on RecipientTrustException {
        /* Require customer bootstrap, never adopt API keys. */
      }
    }
    if (_current) {
      setState(() {
        _state = state;
        _approvalVerified = verified;
        if (raw != null && !verified) {
          _message =
              'This company record is not verified on this device. Obtain a verification record and fingerprint from an independently trusted administrator.';
        }
      });
    }
  }

  List<Map<String, Object?>> get _candidates =>
      ((_state?['candidates'] as List?) ?? [])
          .map((e) => Map<String, Object?>.from(e as Map))
          .toList();
  String _fingerprint(Map<String, Object?> m) => crypto.sha256
      .convert(
        BusinessRecipientApproval.decode(m['publicKeyBase64'] as String, 32),
      )
      .toString();
  Future<String?> _prompt(
    String title,
    String guidance, {
    bool secret = false,
    int lines = 1,
  }) async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(guidance),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  obscureText: secret,
                  maxLines: lines,
                  decoration: InputDecoration(
                    labelText: secret
                        ? 'Recovery passphrase'
                        : 'Verified value',
                  ),
                  autocorrect: false,
                  enableSuggestions: false,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
    } finally {
      controller.clear();
      controller.dispose();
    }
  }

  Future<void> _verifyMember(Map<String, Object?> member) async {
    final supplied = await _prompt(
      'Verify member key',
      'Ask this member to read their full key fingerprint from their device through a trusted channel. Enter that value here.',
    );
    if (supplied == null || !_current) return;
    if (supplied.toLowerCase().replaceAll(' ', '') != _fingerprint(member)) {
      throw const RecipientTrustException(
        'The member fingerprint does not match. Do not approve this key.',
      );
    }
    setState(() => _approved[member['uid'] as String] = Map.from(member));
  }

  Future<void> _bootstrap() async {
    final text = await _prompt(
      'Verify company on this device',
      'Obtain the public verification record directly from a trusted administrator device. Paste it here.',
      lines: 5,
    );
    if (text == null || !_current) return;
    if (text.length > 512 * 1024) {
      throw const RecipientTrustException(
        'The verification record is too large.',
      );
    }
    final approval = BusinessRecipientApproval.fromMap(
      Map<String, Object?>.from(jsonDecode(text) as Map),
    );
    if (approval.companyId != widget.companyId) {
      throw const RecipientTrustException(
        'This record belongs to another company.',
      );
    }
    final fp = await _prompt(
      'Confirm company fingerprint',
      'Compare the full company fingerprint through an independent trusted channel and enter it here.',
    );
    if (fp == null || !_current) return;
    await (await BusinessRecipientTrustRuntime.forApp(
      widget.auth.app,
    )).pinVerified(
      approval,
      verifiedFingerprint: fp.toLowerCase().replaceAll(' ', ''),
    );
    await _load();
    if (_current) {
      setState(() => _message = 'Company verification saved on this device.');
    }
  }

  Future<SecretKey> _accountKey() async {
    final user = widget.auth.currentUser;
    if (user?.uid != _uid) {
      throw const RecipientTrustException('The account changed.');
    }
    final encoded = await LoginPasswordVault.instance
        .restoreStandardEncryptionKey(expectedEmail: user?.email);
    if (encoded == null ||
        !_current ||
        !await LoginPasswordVault.instance.matchesPersistedStandardKey(
          expectedEmail: user?.email,
          expectedKey: encoded,
        )) {
      throw const RecipientTrustException(
        'Unlock encryption in Company files before managing approval keys.',
      );
    }
    return SecretKey(base64Decode(encoded));
  }

  Future<void> _shareKit(
    SimpleKeyPair pair,
    BusinessRecipientApproval approval,
  ) async {
    final password = await _prompt(
      'Protect company approval recovery',
      'Use at least 16 characters. Keep the exported kit separate from its passphrase. RonikCloud cannot replace a lost approval key.',
      secret: true,
    );
    if (password == null || !_current) {
      throw const RecipientTrustException(
        'Save recovery material before enabling protection.',
      );
    }
    final confirm = await _prompt(
      'Confirm recovery passphrase',
      'Enter the same passphrase again.',
      secret: true,
    );
    if (confirm != password) {
      throw const RecipientTrustException('Recovery passphrases do not match.');
    }
    final seed = Uint8List.fromList(await pair.extractPrivateKeyBytes());
    try {
      final kit = await EncryptionRecoveryKitService().create(
        material: StandardEncryptionRecoveryMaterial(
          accountUid: 'business-company:${widget.companyId}',
          environmentId: widget.auth.app.options.projectId,
          encryptionSalt: crypto.sha256
              .convert(BusinessRecipientApproval.decode(approval.publicKey, 32))
              .bytes,
          standardKey: seed,
          createdAt: DateTime.now(),
        ),
        recoveryPassphrase: password,
      );
      if (!mounted || !_current) return;
      final bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'format': 'ronikcloud-company-approval-recovery-v1',
            'approval': approval.toMap(),
            'kit': BusinessRecipientApproval.encode(kit),
          }),
        ),
      );
      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            name: 'ronikcloud-company-approval.ronik-recovery',
            mimeType: 'application/json',
          ),
        ],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      );
      if (!mounted || !_current) return;
      final saved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Recovery kit saved?'),
          content: const Text(
            'Confirm that you saved the encrypted kit and kept its passphrase separately before enabling protection.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('I saved the kit'),
            ),
          ],
        ),
      );
      if (saved != true) {
        throw const RecipientTrustException(
          'Save the recovery kit before enrolling.',
        );
      }
    } finally {
      seed.fillRange(0, seed.length, 0);
    }
  }

  Future<void> _publish() async {
    final trust = await BusinessRecipientTrustRuntime.forApp(widget.auth.app);
    final key = await _accountKey();
    final previous = _state?['recipientTrust'];
    SimpleKeyPair pair;
    if (previous == null) {
      if (_state?['canEnroll'] != true) {
        throw const RecipientTrustException(
          'Only the company owner can enroll protection.',
        );
      }
      pair = await trust.hasSigningKey(widget.companyId)
          ? await trust.signingKey(widget.companyId, key)
          : await Ed25519().newKeyPair();
    } else {
      pair = await trust.signingKey(widget.companyId, key);
    }
    try {
      final approval = await BusinessRecipientApproval.sign(
        companyId: widget.companyId,
        revision: previous == null
            ? 1
            : ((previous as Map)['revision'] as int) + 1,
        members: _approved.values.toList(),
        keyPair: pair,
      );
      if (previous == null) await _shareKit(pair, approval);
      if (!mounted || !_current) return;
      if (previous == null) {
        await trust.savePendingEnrollment(approval, pair, key);
      }
      await _call('publishBusinessRecipientTrust', {
        'approval': approval.toMap(),
      });
      await trust.pinVerified(
        approval,
        verifiedFingerprint: approval.fingerprint,
      );
      await _load();
      if (_current) {
        setState(
          () => _message =
              'Approval published. Older clients must upgrade before new shared writes.',
        );
      }
    } finally {
      pair.destroy();
    }
  }

  Future<void> _recover() async {
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: false,
    );
    final bytes = picked?.files.single.bytes;
    if (bytes == null || !_current) return;
    if (bytes.length > 512 * 1024) {
      throw const RecipientTrustException(
        'Choose a valid approval recovery kit.',
      );
    }
    final wrapper = jsonDecode(utf8.decode(bytes)) as Map;
    if (wrapper['format'] != 'ronikcloud-company-approval-recovery-v1') {
      throw const RecipientTrustException(
        'Choose a company approval recovery kit.',
      );
    }
    final approval = BusinessRecipientApproval.fromMap(
      Map<String, Object?>.from(wrapper['approval'] as Map),
    );
    await approval.verify();
    if (approval.companyId != widget.companyId) {
      throw const RecipientTrustException(
        'This kit belongs to another company.',
      );
    }
    final pass = await _prompt(
      'Open approval recovery kit',
      'Enter the recovery passphrase. It stays on this device.',
      secret: true,
    );
    if (pass == null || !mounted || !_current) return;
    final material = await EncryptionRecoveryKitService().open(
      encodedKit: base64Url.decode(
        base64Url.normalize(wrapper['kit'] as String),
      ),
      recoveryPassphrase: pass,
      expectedAccountUid: 'business-company:${widget.companyId}',
      expectedEnvironmentId: widget.auth.app.options.projectId,
      expectedEncryptionSalt: crypto.sha256
          .convert(BusinessRecipientApproval.decode(approval.publicKey, 32))
          .bytes,
    );
    final pair = await Ed25519().newKeyPairFromSeed(material.standardKey);
    try {
      if (BusinessRecipientApproval.encode(
            (await pair.extractPublicKey()).bytes,
          ) !=
          approval.publicKey) {
        throw const RecipientTrustException(
          'Recovery material does not match.',
        );
      }
      final latest = _state?['recipientTrust'];
      final current = latest == null
          ? approval
          : BusinessRecipientApproval.fromMap(
              Map<String, Object?>.from(latest as Map),
            );
      if (current.publicKey != approval.publicKey) {
        throw const RecipientTrustException(
          'The company key conflicts with this recovery kit.',
        );
      }
      final trust = await BusinessRecipientTrustRuntime.forApp(widget.auth.app);
      await trust.pinVerified(
        current,
        verifiedFingerprint: approval.fingerprint,
      );
      await trust.saveSigningKey(current, pair, await _accountKey());
      await _load();
      if (_current) {
        setState(
          () => _message =
              'Approval key recovered locally. No recovery material was uploaded.',
        );
      }
    } finally {
      pair.destroy();
      material.standardKey.fillRange(0, material.standardKey.length, 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final raw = state?['recipientTrust'];
    final approval = raw == null
        ? null
        : BusinessRecipientApproval.fromMap(
            Map<String, Object?>.from(raw as Map),
          );
    final own = state?['ownIdentity'];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Verify company encryption keys',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text(
          'Verify member keys through an independent trusted channel. Once enrolled, new shared uploads require customer-approved keys. Existing files remain readable.',
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: LinearProgressIndicator(),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(_message!),
          ),
        if (state == null && !_busy)
          TextButton(onPressed: () => _run(_load), child: const Text('Retry')),
        if (own is Map && own['publicKeyBase64'] is String) ...[
          const SizedBox(height: 24),
          Text(
            'Your member key fingerprint',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SelectableText(
            crypto.sha256
                .convert(
                  BusinessRecipientApproval.decode(
                    own['publicKeyBase64'] as String,
                    32,
                  ),
                )
                .toString(),
          ),
        ],
        if (approval != null && _approvalVerified) ...[
          const SizedBox(height: 24),
          Text(
            'Company fingerprint',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SelectableText(approval.fingerprint),
          Text(
            'Approval revision ${approval.revision}. Compare this fingerprint with a trusted administrator device.',
          ),
          ExpansionTile(
            title: const Text('Public verification record'),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(jsonEncode(approval.toMap())),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: _busy ? null : () => _run(_bootstrap),
              child: const Text('Verify this device'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _run(_load),
              child: const Text('Refresh status'),
            ),
            if (state?['canApprove'] == true)
              OutlinedButton(
                onPressed: _busy ? null : () => _run(_recover),
                child: const Text('Recover approval key'),
              ),
          ],
        ),
        if (state?['canApprove'] == true) ...[
          const SizedBox(height: 24),
          Text(
            'Member approvals',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Verify full fingerprints before approving. Removing approval blocks new envelopes; it does not erase access already granted to existing files.',
          ),
          for (final m in _candidates)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(m['uid'] as String),
                    subtitle: Text(
                      (_approved[m['uid']]?['keyId'] == m['keyId']
                              ? 'Verified for: '
                              : 'Needs verification for: ') +
                          (m['scopes'] as List).join(', '),
                    ),
                  ),
                  Wrap(
                    children: [
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() => _verifyMember(m)),
                        child: const Text('Verify key'),
                      ),
                      if (_approved.containsKey(m['uid']))
                        IconButton(
                          tooltip: 'Remove approval',
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: _busy
                              ? null
                              : () =>
                                    setState(() => _approved.remove(m['uid'])),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed:
                  _busy ||
                      (approval != null && !_approvalVerified) ||
                      (_approved.isEmpty && approval == null)
                  ? null
                  : () => _run(_publish),
              child: Text(
                approval == null
                    ? 'Enroll company protection'
                    : 'Publish approved keys',
              ),
            ),
          ),
        ],
      ],
    );
  }
}
