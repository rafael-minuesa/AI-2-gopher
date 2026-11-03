// Standalone Dart AOT executable: no Flutter runtime or interpreter required.
import 'dart:convert';
import 'dart:io';
import 'package:ai_2_gopher/companion/client.dart';
import 'package:ai_2_gopher/companion/protocol.dart';
import 'package:ai_2_gopher/companion/server.dart';

Future<void> installHosts() async {
  final config =
      Platform.environment['XDG_CONFIG_HOME'] ??
      '${Platform.environment['HOME']}/.config';
  if (!config.startsWith('/')) {
    throw const FormatException('XDG_CONFIG_HOME must be absolute');
  }
  final base = {
    'name': hostName,
    'description': 'Gopher Reader local library',
    'path': Platform.resolvedExecutable,
    'type': 'stdio',
  };
  for (final browser in [
    'google-chrome',
    'google-chrome-for-testing',
    'chromium',
    'microsoft-edge',
  ]) {
    final directory = Directory('$config/$browser/NativeMessagingHosts');
    await directory.create(recursive: true);
    await File('${directory.path}/$hostName.json').writeAsString(
      jsonEncode({
        ...base,
        'allowed_origins': ['chrome-extension://$chromiumId/'],
      }),
    );
  }
  final firefoxPath =
      Platform.environment['GOPHER_FIREFOX_HOST_DIR'] ??
      '${Platform.environment['HOME']}/.mozilla/native-messaging-hosts';
  if (!firefoxPath.startsWith('/')) {
    throw const FormatException('GOPHER_FIREFOX_HOST_DIR must be absolute');
  }
  final firefox = Directory(firefoxPath);
  await firefox.create(recursive: true);
  await File('${firefox.path}/$hostName.json').writeAsString(
    jsonEncode({
      ...base,
      'allowed_extensions': [firefoxId],
    }),
  );
  stdout.writeln('Registered Gopher Reader browser integration for this user.');
}

bool allowedCaller(List<String> args) =>
    args.isNotEmpty && args.first == 'chrome-extension://$chromiumId/' ||
    args.length == 2 &&
        args[1] == firefoxId &&
        args.first.endsWith('/$hostName.json');

Future<void> main(List<String> args) async {
  final paths = CompanionPaths.current();
  final client = CompanionClient(paths, Platform.resolvedExecutable);
  if (args.length == 1 && args.first == '--install-browser-hosts') {
    await installHosts();
    return;
  }
  if (args.length == 1 && args.first == '--serve') {
    final server = CompanionServer(paths);
    try {
      await server.start();
      final terminate = ProcessSignal.sigterm.watch().listen((_) {
        server.close();
      });
      final interrupt = ProcessSignal.sigint.watch().listen((_) {
        server.close();
      });
      await server.done.future;
      await terminate.cancel();
      await interrupt.cancel();
    } catch (error) {
      await privateDirectory(paths.root);
      await File('${paths.root}/server.log').writeAsString('$error\n');
      exitCode = 1;
    }
    return;
  }
  if (args.length == 1 &&
      ['--status', '--stop', '--library'].contains(args.first)) {
    final action = {
      '--status': 'status',
      '--stop': 'stop',
      '--library': 'list',
    }[args.first]!;
    try {
      stdout.writeln(
        jsonEncode(
          await client.request({'action': action}, start: action == 'list'),
        ),
      );
    } catch (error) {
      stderr.writeln(error);
      exitCode = 1;
    }
    return;
  }
  if (!allowedCaller(args)) {
    stderr.writeln('Unsupported native messaging caller');
    exitCode = 1;
    return;
  }
  final input = FrameReader(stdin);
  try {
    while (true) {
      final message = await input.next();
      if (message == null) break;
      Map<String, dynamic> response;
      try {
        if (message['protocolVersion'] != 1 || message['action'] != 'import') {
          throw const FormatException('Unsupported browser handoff');
        }
        // Validate and commit the page before launching the GUI.
        response = await client.request(message, start: true);
        final app = File(
          '${File(Platform.resolvedExecutable).parent.path}/gopher_flutter_client',
        );
        if (!await app.exists()) {
          throw const FileSystemException(
            'The native app is missing. Reinstall the complete Linux package.',
          );
        }
        await Process.start(app.path, [
          response['url'] as String,
        ], mode: ProcessStartMode.detached);
      } catch (error) {
        response = {'ok': false, 'error': error.toString()};
      }
      stdout.add(encodeFrame(response));
      await stdout.flush();
    }
  } catch (error) {
    stdout.add(encodeFrame({'ok': false, 'error': error.toString()}));
    await stdout.flush();
  } finally {
    await input.close();
  }
}
