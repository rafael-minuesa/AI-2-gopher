import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'protocol.dart';

class CompanionPaths {
  final String root;
  final String socket;
  CompanionPaths(this.root, this.socket);
  factory CompanionPaths.current() {
    final home = Platform.environment['HOME'];
    final data = Platform.environment['XDG_DATA_HOME'] ?? '$home/.local/share';
    if (home == null || !data.startsWith('/')) {
      throw const FormatException(
        'An absolute user data directory is required',
      );
    }
    final root = '$data/gopher-reader';
    final runtime = Platform.environment['XDG_RUNTIME_DIR'];
    final socket = runtime != null && runtime.startsWith('/')
        ? '$runtime/gopher-reader/control.sock'
        : '$root/control.sock';
    if (utf8.encode(socket).length > 100) {
      throw const FormatException(
        'The local socket path is too long. Set XDG_RUNTIME_DIR to a short user runtime directory.',
      );
    }
    return CompanionPaths(root, socket);
  }
}

Future<void> privateDirectory(String path) async {
  if (await FileSystemEntity.type(path, followLinks: false) ==
      FileSystemEntityType.link) {
    throw const FormatException(
      'The library directory cannot be a symbolic link',
    );
  }
  await Directory(path).create(recursive: true);
  final result = await Process.run('/bin/chmod', ['700', path]);
  if (result.exitCode != 0) {
    throw const FileSystemException('Could not protect the library directory');
  }
}

class CompanionClient {
  final CompanionPaths paths;
  final String executable;
  CompanionClient(this.paths, this.executable);

  Future<Map<String, dynamic>> _send(Map<String, dynamic> message) async {
    final socket = await Socket.connect(
      InternetAddress(paths.socket, type: InternetAddressType.unix),
      0,
      timeout: const Duration(seconds: 1),
    );
    final reader = FrameReader(socket);
    try {
      socket.add(encodeFrame({'protocolVersion': 1, ...message}));
      await socket.flush();
      final response = await reader.next().timeout(const Duration(seconds: 8));
      if (response == null) {
        throw const FormatException('The companion closed the connection');
      }
      if (response['ok'] != true) {
        throw FormatException(
          response['error']?.toString() ?? 'Companion request failed',
        );
      }
      return response;
    } finally {
      await reader.close();
      socket.destroy();
    }
  }

  Future<Map<String, dynamic>> request(
    Map<String, dynamic> message, {
    bool start = false,
  }) async {
    try {
      return await _send(message);
    } on SocketException {
      if (!start) rethrow;
    }
    if (!await File(executable).exists()) {
      throw const FileSystemException(
        'Install the Linux AI-2 Gopher package to enable saved web pages',
      );
    }
    await privateDirectory(paths.root);
    final log = File('${paths.root}/server.log');
    await Process.start(executable, [
      '--serve',
    ], mode: ProcessStartMode.detached);
    for (var attempt = 0; attempt < 40; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        return await _send(message);
      } on SocketException {
        // A concurrent helper may have started the same server.
      }
    }
    var detail = '';
    if (await log.exists()) {
      final lines = await log.readAsLines();
      detail = lines.isEmpty ? '' : ' ${lines.last}';
    }
    throw FormatException('Could not start the local Gopher server.$detail');
  }
}
