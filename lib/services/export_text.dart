import 'dart:io';

/// Only Linux has a Downloads folder this app knows how to find.
bool get canExportText => Platform.isLinux;

/// The folder the desktop calls Downloads, under whatever name it has in this
/// language: ~/Descargas on a Spanish desktop.
String downloadsFolder({
  Map<String, String>? environment,
  String? Function(String path)? read,
}) {
  final env = environment ?? Platform.environment;
  final home = env['HOME'] ?? '.';
  final config = env['XDG_CONFIG_HOME'] ?? '$home/.config';
  String? settings;
  if (read != null) {
    settings = read('$config/user-dirs.dirs');
  } else {
    try {
      settings = File('$config/user-dirs.dirs').readAsStringSync();
    } on FileSystemException {
      settings = null;
    }
  }
  final found = RegExp(
    r'^XDG_DOWNLOAD_DIR="([^"]+)"',
    multiLine: true,
  ).firstMatch(settings ?? '');
  final folder = found?[1]?.replaceFirst(r'$HOME', home);
  // Set to the home folder itself means the desktop has none.
  if (folder == null || folder == home || folder == '$home/') {
    return '$home/Downloads';
  }
  return folder;
}

/// A name for a file from a page's title. The same rule as Export text in the
/// browser extension.
String exportFileName(String title) {
  final plain = title
      .replaceFirst(RegExp(r'^gopher://'), '')
      .replaceAll(RegExp(r'[^\p{L}\p{N}_-]+', unicode: true), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final runes = plain.runes.take(80);
  final short = String.fromCharCodes(runes).replaceFirst(RegExp(r'-+$'), '');
  return short.isEmpty ? 'page' : short;
}

/// Writes [text] as a new file and returns its path. An earlier export is
/// never overwritten: the next one is name-2.txt.
Future<String> exportText(String text, String name, {String? folder}) async {
  final directory = Directory(folder ?? downloadsFolder());
  await directory.create(recursive: true);
  final body = text.endsWith('\n') ? text : '$text\n';
  for (var n = 1; n < 1000; n++) {
    final file = File('${directory.path}/$name${n == 1 ? '' : '-$n'}.txt');
    try {
      await file.create(exclusive: true);
    } on PathExistsException {
      continue;
    } on FileSystemException catch (error) {
      if (error.osError?.errorCode == 17) continue;
      rethrow;
    }
    await file.writeAsString(body, flush: true);
    return file.path;
  }
  throw const FileSystemException('Too many files with this name');
}
