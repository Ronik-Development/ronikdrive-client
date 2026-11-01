import 'package:cloud_storage/src/desktop_drive/drive_relative_path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normal names retain their exact spelling', () {
    final path = DriveRelativePath(['Documents', 'Příloha 🐈.pdf']);
    expect(path.logicalPath, 'Documents/Příloha 🐈.pdf');
    expect(() => path.segments.add('x'), throwsUnsupportedError);
  });
  test(
    'paths cannot escape the provider root or address alternate streams',
    () {
      for (final name in [
        '',
        '.',
        '..',
        '/etc',
        r'..\secret',
        'a/b',
        r'C:\Users',
        'file:stream',
        'a\u0000b',
        'a\nb',
        'a.',
        'a ',
        'CON',
        'con.txt',
        'CON .txt',
        r'CONIN$',
        'LPT1',
        'COM².txt',
        'NUL.txt',
        'a*b',
        String.fromCharCode(0xd800),
        'a' * 256,
        'é' * 128,
      ]) {
        expect(() => DriveRelativePath([name]), throwsFormatException);
      }
      expect(() => DriveRelativePath([]), throwsFormatException);
    },
  );
  test('different cloud names cannot silently overwrite a case variant', () {
    expect(
      () => validateDrivePathBatch([
        DriveRelativePath(['Docs', 'Report.pdf']),
        DriveRelativePath(['docs', 'report.PDF']),
      ]),
      throwsFormatException,
    );
    validateDrivePathBatch([
      DriveRelativePath(['Docs', 'one.pdf']),
      DriveRelativePath(['Docs', 'two.pdf']),
    ]);
  });
  test('validation takes a snapshot of mutable input', () {
    final input = ['safe'];
    final path = DriveRelativePath(input);
    input[0] = '..';
    expect(path.logicalPath, 'safe');
  });
}
