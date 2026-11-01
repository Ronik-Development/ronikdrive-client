const String usernameOnlyAuthDomain = 'users.ronikcloud.invalid';

final RegExp _usernamePattern = RegExp(r'^[a-z0-9][a-z0-9_-]{1,28}[a-z0-9]$');

String normalizeAccountUsername(String value) => value.trim().toLowerCase();

String? validateAccountUsername(String? value) {
  final username = normalizeAccountUsername(value ?? '');
  if (!_usernamePattern.hasMatch(username)) {
    return 'Use 3-30 characters: letters, numbers, hyphens, or underscores; start and end with a letter or number.';
  }
  return null;
}

String usernameOnlyAuthEmail(String username) {
  final normalized = normalizeAccountUsername(username);
  if (validateAccountUsername(normalized) != null) {
    throw ArgumentError.value(username, 'username', 'Invalid account username');
  }
  return '$normalized@$usernameOnlyAuthDomain';
}

bool isUsernameOnlyAuthEmail(String? email) =>
    (email ?? '').trim().toLowerCase().endsWith('@$usernameOnlyAuthDomain');

String authEmailForLoginIdentifier(String identifier) {
  final normalized = identifier.trim().toLowerCase();
  return normalized.contains('@')
      ? normalized
      : usernameOnlyAuthEmail(normalized);
}
