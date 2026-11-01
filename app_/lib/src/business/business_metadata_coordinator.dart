import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../authentication/login_password_vault.dart';
import '../security/business_encryption_registry.dart';
import '../security/business_encryption_service.dart';
import '../security/business_metadata_encryption.dart';
import '../security/encryption_service.dart';
import '../security/encryption_setup_service.dart';
import 'company_admin_service.dart';

class BusinessMetadataCoordinatorException
    implements Exception, CompanyMetadataProtectionFailure {
  const BusinessMetadataCoordinatorException(this.message);

  @override
  final String message;

  @override
  String toString() => 'BusinessMetadataCoordinatorException: $message';
}

class BusinessMetadataCoordinator implements CompanyMetadataProtection {
  BusinessMetadataCoordinator({
    required this.user,
    required this.firestore,
    required BusinessEncryptionRegistry registry,
    required EncryptionSetupService encryptionSetupService,
    BusinessMetadataEncryptionService? metadataEncryptionService,
  }) : _registry = registry,
       _encryptionSetupService = encryptionSetupService,
       _metadataEncryptionService =
           metadataEncryptionService ?? BusinessMetadataEncryptionService();

  factory BusinessMetadataCoordinator.forApp({
    required FirebaseApp app,
    required User user,
    required FirebaseFirestore firestore,
  }) {
    return BusinessMetadataCoordinator(
      user: user,
      firestore: firestore,
      registry: BusinessEncryptionRegistry.forApp(app),
      encryptionSetupService: EncryptionSetupService.forApp(app),
    );
  }

  final User user;
  final FirebaseFirestore firestore;
  final BusinessEncryptionRegistry _registry;
  final EncryptionSetupService _encryptionSetupService;
  final BusinessMetadataEncryptionService _metadataEncryptionService;

  SecretKey? _cachedAccountProtectionKey;
  BusinessEncryptionIdentity? _cachedIdentity;

  @override
  Future<CompanySession> decryptSession(CompanySession session) async {
    await _prepareIdentityIfPossible();
    final company = session.company;
    final decryptedCompany = company == null
        ? null
        : await _decryptCompany(company);
    final decryptedGroups = <CompanyGroup>[];
    for (final group in session.groups) {
      decryptedGroups.add(await _decryptGroup(group));
    }
    return session.copyWith(
      company: decryptedCompany,
      groups: List<CompanyGroup>.unmodifiable(decryptedGroups),
    );
  }

  @override
  Future<CompanyDashboard> decryptDashboard(CompanyDashboard dashboard) async {
    await _prepareIdentityIfPossible();
    final company = dashboard.company;
    final decryptedCompany = company == null
        ? null
        : await _decryptCompany(company);
    final decryptedGroups = <CompanyGroup>[];
    for (final group in dashboard.groups) {
      decryptedGroups.add(await _decryptGroup(group));
    }
    decryptedGroups.sort(
      (first, second) =>
          first.name.toLowerCase().compareTo(second.name.toLowerCase()),
    );
    return dashboard.copyWith(
      company: decryptedCompany,
      groups: List<CompanyGroup>.unmodifiable(decryptedGroups),
    );
  }

  @override
  Future<Map<String, Object?>> prepareCompanyCreate({
    required String name,
    String? domain,
  }) async {
    final accountKey = await _accountProtectionKey();
    final identity = await _ensureIdentity(accountKey);
    final prepared = await _metadataEncryptionService.prepare(
      entityType: 'company',
      plaintext: BusinessMetadataPlaintext(name: name, domain: domain),
      recipients: <BusinessEncryptionRecipient>[_recipientForUser(identity)],
    );
    return <String, Object?>{
      'identity': identity.toMap(),
      'encryptedMetadata': prepared.toMap(),
    };
  }

  @override
  Future<Map<String, Object?>> prepareCompanyUpdate({
    required CompanyProfile company,
    required String name,
    String? domain,
  }) async {
    final recipients = await _registry.listMetadataRecipients(
      entityType: 'company',
    );
    _requireCurrentRecipient(recipients.recipients);
    final current = company.encryptedMetadata;
    final prepared = await _metadataEncryptionService.prepare(
      entityType: 'company',
      plaintext: BusinessMetadataPlaintext(name: name, domain: domain),
      recipients: recipients.recipients,
      contextId: current?.contextId,
      generation: (current?.generation ?? 0) + 1,
    );
    return <String, Object?>{'encryptedMetadata': prepared.toMap()};
  }

  @override
  Future<Map<String, Object?>> prepareGroupWrite({
    required String name,
    String? description,
    required List<String> memberUids,
    CompanyGroup? existing,
  }) async {
    final recipients = await _registry.listMetadataRecipients(
      entityType: 'group',
      memberUids: memberUids,
    );
    _requireCurrentRecipient(recipients.recipients);
    final current = existing?.encryptedMetadata;
    final prepared = await _metadataEncryptionService.prepare(
      entityType: 'group',
      plaintext: BusinessMetadataPlaintext(
        name: name,
        description: description,
      ),
      recipients: recipients.recipients,
      contextId: current?.contextId,
      generation: (current?.generation ?? 0) + 1,
    );
    return <String, Object?>{'encryptedMetadata': prepared.toMap()};
  }

  @override
  Future<int> refreshMetadataAccess({
    required CompanyProfile company,
    CompanyGroup? group,
  }) async {
    final metadata = group?.encryptedMetadata ?? company.encryptedMetadata;
    if (metadata == null || !metadata.readable) {
      throw const BusinessMetadataCoordinatorException(
        'This device cannot open the protected labels yet. Ask a current '
        'authorized member to refresh label access.',
      );
    }
    final entityType = group == null ? 'company' : 'group';
    final state = await _registry.listMetadataRecipients(
      entityType: entityType,
      groupId: group?.id,
    );
    if (state.metadataMissingUids.isEmpty) {
      return 0;
    }
    final missingSet = state.metadataMissingUids.toSet();
    final missingRecipients = state.recipients
        .where((recipient) => missingSet.contains(recipient.uid))
        .toList(growable: false);
    if (missingRecipients.length != state.metadataMissingUids.length) {
      throw const BusinessMetadataCoordinatorException(
        'Protected label recipient state changed. Refresh and try again.',
      );
    }
    final accountKey = await _accountProtectionKey();
    final identity = await _ensureIdentity(accountKey);
    final metadataKey = await _metadataEncryptionService.openMetadataKey(
      metadata: metadata,
      currentUid: user.uid,
      identity: identity,
      accountProtectionKey: accountKey,
    );
    final additions = await _metadataEncryptionService.wrapForRecipients(
      metadata: metadata,
      metadataKey: metadataKey,
      recipients: missingRecipients,
    );
    final result = await _registry.appendMetadataEnvelopes(
      entityType: entityType,
      groupId: group?.id,
      additions: additions,
    );
    return result.addedCount;
  }

  Future<CompanyProfile> _decryptCompany(CompanyProfile company) async {
    final metadata = company.encryptedMetadata;
    if (!company.metadataProtected) {
      return company;
    }
    if (metadata == null || !metadata.readable) {
      await _prepareIdentityIfPossible();
      return company.copyWith(
        name: 'Protected company',
        clearDomain: true,
        metadataReadable: false,
      );
    }
    try {
      final plaintext = await _open(metadata);
      return company.copyWith(
        name: plaintext.name,
        domain: plaintext.domain,
        clearDomain: plaintext.domain == null,
        metadataReadable: true,
      );
    } on Object {
      return company.copyWith(
        name: 'Protected company',
        clearDomain: true,
        metadataReadable: false,
      );
    }
  }

  Future<CompanyGroup> _decryptGroup(CompanyGroup group) async {
    final metadata = group.encryptedMetadata;
    if (!group.metadataProtected) {
      return group;
    }
    if (metadata == null || !metadata.readable) {
      return group.copyWith(
        name: 'Protected group',
        clearDescription: true,
        metadataReadable: false,
      );
    }
    try {
      final plaintext = await _open(metadata);
      return group.copyWith(
        name: plaintext.name,
        description: plaintext.description,
        clearDescription: plaintext.description == null,
        metadataReadable: true,
      );
    } on Object {
      return group.copyWith(
        name: 'Protected group',
        clearDescription: true,
        metadataReadable: false,
      );
    }
  }

  Future<BusinessMetadataPlaintext> _open(
    BusinessEncryptedMetadata metadata,
  ) async {
    final accountKey = await _accountProtectionKey();
    final identity = await _ensureIdentity(accountKey);
    return _metadataEncryptionService.open(
      metadata: metadata,
      currentUid: user.uid,
      identity: identity,
      accountProtectionKey: accountKey,
    );
  }

  Future<void> _prepareIdentityIfPossible() async {
    if (_cachedIdentity != null) {
      return;
    }
    try {
      final accountKey = await _accountProtectionKey();
      await _ensureIdentity(accountKey);
    } on Object {
      // Missing label access is still represented explicitly in the returned
      // model. Identity bootstrap is best effort so dashboard reads never
      // turn into password or recovery prompts.
    }
  }

  Future<BusinessEncryptionIdentity> _ensureIdentity(
    SecretKey accountKey,
  ) async {
    final cached = _cachedIdentity;
    if (cached != null) {
      return cached;
    }
    try {
      final identity = await _registry.ensureIdentity(
        accountProtectionKey: accountKey,
      );
      _cachedIdentity = identity;
      return identity;
    } on BusinessEncryptionRegistryException catch (error) {
      throw BusinessMetadataCoordinatorException(error.message);
    }
  }

  BusinessEncryptionRecipient _recipientForUser(
    BusinessEncryptionIdentity identity,
  ) {
    return BusinessEncryptionRecipient(
      uid: user.uid,
      keyId: identity.keyId,
      publicKeyBase64: identity.publicKeyBase64,
    );
  }

  void _requireCurrentRecipient(List<BusinessEncryptionRecipient> recipients) {
    if (!recipients.any((recipient) => recipient.uid == user.uid)) {
      throw const BusinessMetadataCoordinatorException(
        'Set up Business encryption on this device before saving protected '
        'company or group labels.',
      );
    }
  }

  Future<SecretKey> _accountProtectionKey() async {
    final cached = _cachedAccountProtectionKey;
    if (cached != null) {
      return cached;
    }
    final email = user.email;
    final restored = await LoginPasswordVault.instance
        .restoreStandardEncryptionKey(expectedEmail: email);
    final restoredKey = _decodeKey(restored);
    if (restoredKey != null) {
      _cachedAccountProtectionKey = restoredKey;
      return restoredKey;
    }

    Uint8List? salt;
    try {
      final snapshot = await firestore.collection('users').doc(user.uid).get();
      final encodedSalt = snapshot.data()?['encryptionSalt'];
      if (encodedSalt is String && encodedSalt.trim().isNotEmpty) {
        salt = Uint8List.fromList(base64Decode(encodedSalt.trim()));
      }
    } on FormatException {
      throw const BusinessMetadataCoordinatorException(
        'The account encryption setup is damaged. Contact support before '
        'changing protected Business labels.',
      );
    }
    final password = await LoginPasswordVault.instance.restore(
      expectedEmail: email,
    );
    if (password == null || password.isEmpty) {
      throw const BusinessMetadataCoordinatorException(
        'Unlock encryption in Company files on this device before changing '
        'protected Business labels.',
      );
    }
    salt ??= await _encryptionSetupService.ensureStandardEncryptionSalt();
    final key = await EncryptionService.instance.deriveKey(
      password: password,
      salt: salt,
    );
    final keyBytes = await key.extractBytes();
    if (keyBytes.length != 32) {
      throw const BusinessMetadataCoordinatorException(
        'The account encryption key has an invalid length.',
      );
    }
    LoginPasswordVault.instance.storeStandardEncryptionKey(
      email: email,
      key: base64Encode(keyBytes),
      salt: salt,
    );
    _cachedAccountProtectionKey = key;
    return key;
  }

  SecretKey? _decodeKey(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    try {
      final bytes = base64Decode(value.trim());
      return bytes.length == 32 ? SecretKey(bytes) : null;
    } on FormatException {
      return null;
    }
  }
}
