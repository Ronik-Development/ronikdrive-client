import 'dart:convert';

/// Validates names before a native provider maps cloud metadata onto disk.
///
/// Applies the shared Windows/macOS subset. Never silently sanitize names:
/// doing so could map two cloud items to the same local file. Providers must
/// also reject symlinks/reparse points and verify the resolved parent belongs
/// to their registered root at the time of each filesystem operation.
class DriveRelativePath {
  DriveRelativePath(Iterable<String> segments)
    : segments = List<String>.unmodifiable(segments) {
    if (this.segments.isEmpty) {
      throw const FormatException('A drive item needs a relative path.');
    }
    for (final segment in this.segments) {
      if (!_isPortableSegment(segment)) {
        throw const FormatException('Unsupported desktop drive name.');
      }
    }
  }

  final List<String> segments;

  /// Logical path only. Native adapters join validated segments under their
  /// owned root; never concatenate an untrusted server path to an absolute path.
  String get logicalPath => segments.join('/');

  // Conservative ASCII case collision check; native providers additionally
  // use volume-specific Unicode normalization and filename equivalence.
  String get collisionKey => logicalPath.toLowerCase();
}

bool _isPortableSegment(String name) {
  if (name.isEmpty ||
      name == '.' ||
      name == '..' ||
      name.length > 255 ||
      utf8.encode(name).length > 255 ||
      name.endsWith('.') ||
      name.endsWith(' ')) {
    return false;
  }
  if (RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]').hasMatch(name)) return false;
  // Windows reserves device basenames even when an extension is present.
  final base = name.split('.').first.trimRight().toUpperCase();
  if (const {
    'CON',
    'PRN',
    'AUX',
    'NUL',
    r'CONIN$',
    r'CONOUT$',
  }.contains(base)) {
    return false;
  }
  if (RegExp(r'^(COM|LPT)[1-9¹²³]$').hasMatch(base)) return false;
  // Reject malformed UTF-16 before passing it across a native API boundary.
  final units = name.codeUnits;
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
        return false;
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    }
  }
  return true;
}

/// Reject ambiguous mappings before publishing a batch of placeholders.
/// Stable item IDs belong in the provider database, never inferred from names.
void validateDrivePathBatch(Iterable<DriveRelativePath> paths) {
  final seen = <String>{};
  for (final path in paths) {
    if (!seen.add(path.collisionKey)) {
      throw const FormatException('Desktop drive names collide.');
    }
  }
}
