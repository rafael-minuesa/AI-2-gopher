import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_2_gopher/models/gopher_item.dart';
import 'package:ai_2_gopher/services/gopher_client.dart';

void main() {
  late ServerSocket server;
  late StreamSubscription<Socket> connections;
  final sockets = <Socket>[];
  late GopherAddress address;

  Future<void> serve(Future<void> Function(Socket, String) respond) async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    address = GopherAddress(
      host: '127.0.0.1',
      port: server.port,
      selector: '/hello',
      type: GopherItemType.file,
    );
    connections = server.listen((socket) {
      sockets.add(socket);
      socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .then((request) => respond(socket, request));
    });
    addTearDown(() async {
      for (final socket in sockets) {
        socket.destroy();
      }
      sockets.clear();
      await connections.cancel();
      await server.close();
    });
  }

  test(
    'menu parsing stops at terminator and ignores malformed destinations',
    () {
      final rows = GopherClient().parseMenu(
        'iWelcome\r\n1Docs\t/docs\texample.org\t70\r\n'
        '1Missing fields\r\n1Bad port\t/\texample.org\t0\r\n'
        '.\r\n0After terminator\t/late\texample.org\t70\r\n',
      );
      expect(rows.map((row) => row.displayText), ['Welcome', 'Docs']);
    },
  );

  test(
    'text sends only selector, unstuffs periods and stops before socket close',
    () async {
      await serve((socket, request) async {
        expect(request, '/hello');
        for (final byte in utf8.encode('Hello\r\n..leading period\r\n.\r\n')) {
          socket.add([byte]);
          await socket.flush();
        }
        // Deliberately leave open; a framed response should finish immediately.
      });
      final text = await GopherClient(
        timeout: const Duration(seconds: 2),
      ).fetchText(address);
      expect(text, 'Hello\n.leading period');
    },
  );

  test('search sends a tab-delimited query', () async {
    await serve((socket, request) async {
      expect(request, '/hello\ttwo words');
      socket.write('0Result\t/readme\texample.org\t70\r\n.\r\n');
      await socket.flush();
    });
    final rows = await GopherClient().search(address, 'two words');
    expect(rows.single.displayText, 'Result');
  });

  test('legacy text decoding preserves non-UTF8 bytes', () async {
    await serve((socket, request) async {
      socket.add([0x63, 0x61, 0x66, 0xe9, 13, 10, 46, 13, 10]);
      await socket.flush();
    });
    expect(await GopherClient().fetchText(address), 'café');
  });

  test('binary content preserves dot sequences', () async {
    final bytes = [0, 255, 13, 10, 46, 13, 10, 1];
    await serve((socket, request) async {
      socket.add(bytes);
      await socket.flush();
      await socket.close();
    });
    expect(await GopherClient().fetchBinary(address), bytes);
  });

  test('binary reads have an absolute response deadline', () async {
    await serve((socket, request) async {});
    final client = GopherClient(timeout: const Duration(milliseconds: 200));
    await expectLater(
      client.fetchBinary(address),
      throwsA(
        isA<GopherException>().having(
          (e) => e.message,
          'message',
          contains('timed out'),
        ),
      ),
    );
  });

  test('oversized responses fail without unbounded buffering', () async {
    await serve((socket, request) async {
      socket.write('A response too large\r\n.\r\n');
      await socket.flush();
    });
    await expectLater(
      GopherClient(maxResponseBytes: 8).fetchText(address),
      throwsA(
        isA<GopherException>().having(
          (e) => e.message,
          'message',
          contains('size limit'),
        ),
      ),
    );
  });

  GopherAddress question() => GopherAddress(
    host: '127.0.0.1',
    port: server.port,
    selector: '/chat',
    type: GopherItemType.search,
    query: 'who are you',
  );

  test('menu lines reach the caller as they arrive, split or not', () async {
    final second = Completer<void>();
    await serve((socket, request) async {
      socket.write('iRead');
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      socket.write('ing\r\n');
      await socket.flush();
      await second.future;
      socket.add(utf8.encode('iAdi\u00f3s\r\n'));
      socket.write('.\r\n');
      await socket.flush();
    });
    final seen = <List<String>>[];
    final rows = await GopherClient().fetchMenu(
      question(),
      onPartial: (soFar) {
        seen.add(soFar.map((row) => row.displayText).toList());
        if (!second.isCompleted) second.complete();
      },
    );
    expect(seen.first, ['Reading']);
    expect(rows.map((row) => row.displayText), ['Reading', 'Adi\u00f3s']);
  });

  test('a character split across chunks waits for the rest', () async {
    final bytes = utf8.encode('iAdi\u00f3s\r\n.\r\n');
    final cut = bytes.indexOf(0xc3) + 1;
    await serve((socket, request) async {
      socket.add(bytes.sublist(0, cut));
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      socket.add(bytes.sublist(cut));
      await socket.flush();
    });
    final seen = <String>[];
    final rows = await GopherClient().fetchMenu(
      question(),
      onPartial: (soFar) => seen.add(soFar.last.displayText),
    );
    expect(rows.single.displayText, 'Adi\u00f3s');
    expect(seen, everyElement('Adi\u00f3s'));
  });

  test('a local question outlasts the deadline while lines arrive', () async {
    await serve((socket, request) async {
      for (var i = 0; i < 4; i++) {
        socket.write('iLine\r\n');
        await socket.flush();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      socket.write('.\r\n');
      await socket.flush();
    });
    final rows = await GopherClient(
      timeout: const Duration(milliseconds: 150),
      answerSilence: const Duration(seconds: 2),
    ).fetchMenu(question());
    expect(rows.length, 4);
  });

  test('a local question that goes silent still ends', () async {
    await serve((socket, request) async {
      socket.write('iReading\r\n');
      await socket.flush();
    });
    await expectLater(
      GopherClient(
        answerSilence: const Duration(milliseconds: 150),
      ).fetchMenu(question()),
      throwsA(isA<GopherException>()),
    );
  });

  test('a question to another computer keeps the deadline', () {
    expect(question().isLocalQuestion, isTrue);
    expect(
      GopherAddress(
        host: 'gopher.example.org',
        selector: '/s',
        type: GopherItemType.search,
        query: 'x',
      ).isLocalQuestion,
      isFalse,
    );
    expect(
      GopherAddress(host: '127.0.0.1', selector: '/menu').isLocalQuestion,
      isFalse,
    );
  });

  test(
    'an answer cut short says so, and other servers may omit the end',
    () async {
      await serve((socket, request) async {
        socket.write('iHalf an answer\t\t\t0\r\n');
        await socket.flush();
        await socket.close();
      });
      final port = server.port;
      await expectLater(
        GopherClient().fetchMenu(
          GopherAddress(
            host: '127.0.0.1',
            port: port,
            selector: '/chat',
            type: GopherItemType.search,
            query: 'hello',
          ),
        ),
        throwsA(
          isA<GopherException>().having(
            (e) => e.message,
            'message',
            contains('stopped before it finished'),
          ),
        ),
      );
      final menu = await GopherClient().fetchMenu(
        GopherAddress(host: '127.0.0.1', port: port),
      );
      expect(menu.single.displayText, 'Half an answer');
    },
  );

  test('cancelling a silent question closes it at once', () async {
    final started = Completer<void>();
    await serve((socket, request) async {
      socket.write('iReading\r\n');
      await socket.flush();
      started.complete();
    });
    final request = GopherRequest();
    final response = GopherClient().fetchMenu(question(), request: request);
    final assertion = expectLater(response, throwsA(isA<GopherException>()));
    await started.future;
    request.cancel();
    await assertion.timeout(const Duration(seconds: 2));
  });

  test('cancellation closes an in-flight connection', () async {
    final started = Completer<void>();
    await serve((socket, request) async {
      started.complete();
    });
    final request = GopherRequest();
    final response = GopherClient().fetchBinary(address, request: request);
    final assertion = expectLater(response, throwsA(isA<GopherException>()));
    await started.future;
    request.cancel();
    await assertion;
  });
}
