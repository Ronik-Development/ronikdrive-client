import 'dart:convert';
import 'package:crypto/crypto.dart';

/// An opaque destination identity kept only in the account's encrypted journal.
String uploadResumeContext({
  required String uid,
  required String storageScope,
  required String? groupId,
  required String? folderId,
  required List<String> relativeFolders,
  required bool secure,
}) => sha256
    .convert(
      utf8.encode(
        jsonEncode([
          uid,
          storageScope,
          groupId,
          folderId,
          relativeFolders,
          secure,
        ]),
      ),
    )
    .toString();
