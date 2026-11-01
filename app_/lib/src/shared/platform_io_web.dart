// platform_io_web.dart
// Stub implementation for Web

import 'dart:async';
import 'dart:typed_data';

class Platform {
  static const bool isWindows = false;
  static const bool isLinux = false;
  static const bool isMacOS = false;
  static const bool isAndroid = false;
  static const bool isIOS = false;
  static const bool isFuchsia = false;
  static String get operatingSystem => 'web';
  static String get pathSeparator => '/';
  static String get resolvedExecutable => '';
  static String get executable => '';
}

class Directory {
  final String path;
  Directory(this.path);
  static Directory get current => Directory('');
  Future<bool> exists() async => false;
  Future<void> create({bool recursive = false}) async {}
  Stream<FileSystemEvent> watch({
    int events = FileSystemEvent.all,
    bool recursive = false,
  }) => const Stream.empty();
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) => const Stream.empty();
}

class FileSystemEntity {
  final String path;
  FileSystemEntity(this.path);
  static Future<FileSystemEntityType> type(
    String path, {
    bool followLinks = true,
  }) async => FileSystemEntityType.notFound;
  Future<FileStat> stat() async => FileStat();
  Future<void> delete({bool recursive = false}) async {}
}

enum FileSystemEntityType { file, directory, link, notFound }

class File extends FileSystemEntity {
  File(super.path);
  Future<bool> exists() async => false;
  Future<int> length() async => 0;
  Future<DateTime> lastModified() async => DateTime.now();
  Future<void> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async {}
  Future<void> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async {}
  Future<void> create({bool recursive = false}) async {}
  IOSink openWrite({FileMode mode = FileMode.write}) => IOSink();
  Stream<List<int>> openRead([int? start, int? end]) => const Stream.empty();
  @override
  Future<void> delete({bool recursive = false}) async {}
  Future<Uint8List> readAsBytes() async => Uint8List(0);
  Future<String> readAsString() async => '';
}

class IOSink implements Sink<List<int>>, StreamConsumer<List<int>> {
  @override
  void add(List<int> data) {}
  @override
  Future<void> close() async {}
  Future<void> flush() async {}
  @override
  Future<void> addStream(Stream<List<int>> stream) async {}
}

class FileMode {
  static const write = FileMode._();
  const FileMode._();
}

class FileStat {
  DateTime get modified => DateTime.now();
  int get size => 0;
}

class FileSystemEvent {
  static const int all = 7;
  final String path;
  final bool isDirectory;
  FileSystemEvent(this.path, {this.isDirectory = false});
}

class FileSystemCreateEvent extends FileSystemEvent {
  FileSystemCreateEvent(super.path, {super.isDirectory});
}

class FileSystemModifyEvent extends FileSystemEvent {
  final bool contentChanged;
  FileSystemModifyEvent(
    super.path, {
    super.isDirectory,
    this.contentChanged = true,
  });
}

class FileSystemDeleteEvent extends FileSystemEvent {
  FileSystemDeleteEvent(super.path, {super.isDirectory});
}

class FileSystemMoveEvent extends FileSystemEvent {
  final String? destination;
  FileSystemMoveEvent(super.path, this.destination, {super.isDirectory});
}

class FileSystemException implements Exception {
  final String message;
  const FileSystemException(this.message);
  @override
  String toString() => 'FileSystemException: $message';
}

class Process {
  final int pid = 0;

  static Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) async {
    return ProcessResult(0, 0, '', '');
  }

  static Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) async {
    return Process();
  }
}

class ProcessStartMode {
  static const normal = ProcessStartMode._('normal');
  static const detached = ProcessStartMode._('detached');

  final String name;
  const ProcessStartMode._(this.name);
}

class ProcessResult {
  final int pid;
  final int exitCode;
  final dynamic stdout;
  final dynamic stderr;
  ProcessResult(this.pid, this.exitCode, this.stdout, this.stderr);
}

abstract class Encoding {}
