const Set<String> _protectedCompanyLabels = <String>{
  'encrypted company',
  'protected company',
};

const Set<String> _protectedGroupLabels = <String>{
  'encrypted group',
  'protected group',
};

String businessCompanyStorageLabel(String? decryptedLabel) {
  final label = decryptedLabel?.trim();
  if (label == null || label.isEmpty) {
    return 'Company shared files';
  }
  if (_protectedCompanyLabels.contains(label.toLowerCase())) {
    return 'Protected company files';
  }
  return '$label shared files';
}

String businessGroupStorageLabel(
  String? decryptedLabel, {
  required int protectedOrdinal,
}) {
  final label = decryptedLabel?.trim();
  if (label != null &&
      label.isNotEmpty &&
      !_protectedGroupLabels.contains(label.toLowerCase())) {
    return '$label files';
  }
  final suffix = protectedOrdinal > 0 ? ' $protectedOrdinal' : '';
  return 'Protected group$suffix files';
}
