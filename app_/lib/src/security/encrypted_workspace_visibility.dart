bool containsOpaqueEncryptedLabel(String? value) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) {
    return false;
  }
  return RegExp(r'(^|[._-])enc--[A-Za-z0-9_-]{16,}').hasMatch(normalized);
}

String safeEncryptedDisplayLabel({
  required String placeholder,
  String? encryptedLabel,
  String? candidate,
}) {
  final normalizedPlaceholder = placeholder.trim().isEmpty
      ? 'Encrypted item'
      : placeholder.trim();
  final normalizedCandidate = candidate?.trim() ?? '';
  if (normalizedCandidate.isEmpty ||
      containsOpaqueEncryptedLabel(normalizedCandidate)) {
    return normalizedPlaceholder;
  }

  final normalizedEncryptedLabel = encryptedLabel?.trim() ?? '';
  if (normalizedEncryptedLabel.isNotEmpty &&
      normalizedCandidate == normalizedEncryptedLabel) {
    return normalizedPlaceholder;
  }
  return normalizedCandidate;
}

bool requiresStandardWorkspaceKeyForLabel({
  required bool isSecured,
  required bool hasEncryptedLabel,
  required bool hasEmbeddedEncryptedLabel,
  required bool hasMemberKeyEnvelopes,
}) {
  return !isSecured &&
      !hasMemberKeyEnvelopes &&
      (hasEncryptedLabel || hasEmbeddedEncryptedLabel);
}
