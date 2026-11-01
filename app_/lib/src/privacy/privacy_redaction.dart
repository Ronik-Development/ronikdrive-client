String redactDiagnosticText(String value) {
  var output = value;
  const keyedPrivateFields = [
    'clientSecret',
    'idToken',
    'access_token',
    'accessToken',
    'secretAccessKey',
    'secretKey',
    'password',
    'passphrase',
    'privateKey',
    'recoveryKey',
    'uid',
    'user',
    'userId',
    'user_id',
    'owner',
    'ownerUid',
    'owner_uid',
    'objectKey',
    'object_key',
    'fileName',
    'file_name',
    'fileId',
    'file_id',
    'folderName',
    'folder_name',
    'folderId',
    'folder_id',
    'localPath',
    'local_path',
    'remoteFolder',
    'remote_folder',
    'displayName',
    'display_name',
    'companyName',
    'company_name',
    'companyId',
    'company_id',
    'workspaceName',
    'workspace_name',
    'bucket',
    'endpoint',
  ];
  for (final key in keyedPrivateFields) {
    final escapedKey = RegExp.escape(key);
    output = output.replaceAllMapped(
      RegExp(
        "(\\b$escapedKey\\b\\s*(?:[:=]\\s*|\\s+))"
        "('[^'\\r\\n]*'|\"[^\"\\r\\n]*\"|[^\\s,}\\]\\r\\n]+)",
        caseSensitive: false,
      ),
      (match) => '${match.group(1) ?? '$key='}<redacted>',
    );
    output = output.replaceAll(
      RegExp('($escapedKey=)[^&\\s]+', caseSensitive: false),
      '$key=<redacted>',
    );
    output = output.replaceAll(
      RegExp('("$escapedKey"\\s*:\\s*")[^"]*(")', caseSensitive: false),
      '"$key":"<redacted>"',
    );
  }
  output = output.replaceAll(
    RegExp(r'\bBearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
    'Bearer <redacted>',
  );
  output = output.replaceAll(
    RegExp(
      r'\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}(?:\.[A-Za-z0-9_-]{5,})?\b',
    ),
    '<token-redacted>',
  );
  output = output.replaceAll(
    RegExp(r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', caseSensitive: false),
    '<email-redacted>',
  );
  output = output.replaceAll(
    RegExp(r'https?://[^\s]+', caseSensitive: false),
    '<url-redacted>',
  );
  output = output.replaceAll(
    RegExp(
      r'\b(?:user_[a-f0-9]{32}|company_[a-f0-9]{28})/(?:[^\s,;)}\]]+)',
      caseSensitive: false,
    ),
    '<object-ref-redacted>',
  );
  output = output.replaceAll(
    RegExp(r'\benc--[A-Za-z0-9_-]{16,}\b'),
    '<encrypted-label-redacted>',
  );
  output = output.replaceAll(
    RegExp(r'''["'][A-Za-z]:\\[^"'\r\n]+["']'''),
    '<path-redacted>',
  );
  // Runtime failures often append an exception type to an unquoted path.
  // Match that boundary before the whitespace-bounded fallback so directory
  // and file labels containing spaces cannot survive as trailing text.
  output = output.replaceAll(
    RegExp(
      r'(?<![A-Za-z0-9])[A-Za-z]:\\[^\r\n]*?(?=:\s+[A-Za-z_][A-Za-z0-9_]*(?:Exception|Error)\b)',
      caseSensitive: false,
    ),
    '<path-redacted>',
  );
  // Stack frames commonly use an unquoted absolute Windows path followed by
  // a line (and optionally column) number. Match that complete form before
  // the conservative whitespace-bounded fallback so labels inside directory
  // names cannot survive as trailing text.
  output = output.replaceAll(
    RegExp(
      r'(?<![A-Za-z0-9])[A-Za-z]:\\[^\r\n,;)}\]]*?:\d+(?::\d+)?',
      caseSensitive: false,
    ),
    '<path-redacted>',
  );
  output = output.replaceAll(
    RegExp(
      r'(?<![A-Za-z0-9])[A-Za-z]:\\[^\s\r\n,;)}\]]+',
      caseSensitive: false,
    ),
    '<path-redacted>',
  );
  output = output.replaceAll(
    RegExp(r'''["']/(?:[^"'\r\n]+)["']'''),
    '<path-redacted>',
  );
  output = output.replaceAll(
    RegExp(
      r'(?<![A-Za-z0-9:/])/(?:[^\r\n]*?)(?=:\s+[A-Za-z_][A-Za-z0-9_]*(?:Exception|Error)\b)',
      caseSensitive: false,
    ),
    '<path-redacted>',
  );
  output = output.replaceAll(
    RegExp(r'(?<![A-Za-z0-9:])/(?:[^/\s]+/)+[^\s,;)}\]]+'),
    '<path-redacted>',
  );
  output = output.replaceAll(
    RegExp(
      r'''(?<![A-Za-z0-9@/])["']?[A-Za-z0-9][A-Za-z0-9 _().-]{0,120}\.[A-Za-z0-9]{1,12}["']?''',
    ),
    '<file-redacted>',
  );
  return output;
}
