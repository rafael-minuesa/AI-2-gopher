import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_2_gopher/companion/client.dart';
import 'package:ai_2_gopher/companion/library.dart';
import 'package:ai_2_gopher/companion/protocol.dart';
import 'package:ai_2_gopher/companion/server.dart';
import 'package:ai_2_gopher/models/gopher_item.dart';
import 'package:ai_2_gopher/services/gopher_client.dart';

const firstId = '11111111-1111-4111-8111-111111111111';
const secondId = '22222222-2222-4222-8222-222222222222';
Map<String, dynamic> page({
  String url = 'https://example.org/first',
  List<dynamic> links = const [],
}) => {
  'url': url,
  'title': 'A quiet café\twith a title\n',
  'capturedAt': '2026-10-09T12:00:00Z',
  'article': 'A quiet café\n.\n..dots\nFinal line',
  'page': 'Full page\n\tTable cell',
  'links': links,
};

void main() {
  test(
    'native frames survive split headers and UTF-8 bodies, including multiple messages',
    () async {
      final messages = [
        {'title': 'café 日本語'},
        {'ok': true},
      ];
      final bytes = messages.expand(encodeFrame).toList();
      final reader = FrameReader(
        Stream.fromIterable(bytes.map((byte) => [byte])),
      );
      expect(await reader.next(), messages.first);
      expect(await reader.next(), messages.last);
      expect(await reader.next(), isNull);
      await reader.close();
    },
  );

  test(
    'invalid, truncated and oversized native frames are rejected before allocating bodies',
    () async {
      for (final bytes in [
        [1, 0],
        [
          ...(ByteData(4)..setUint32(0, maxMessageBytes + 1, Endian.host))
              .buffer
              .asUint8List(),
        ],
        [
          ...(ByteData(4)..setUint32(0, 2, Endian.host)).buffer.asUint8List(),
          123,
        ],
      ]) {
        final reader = FrameReader(Stream.value(bytes));
        await expectLater(reader.next(), throwsFormatException);
        await reader.close();
      }
    },
  );

  group('local companion', () {
    late Directory root;
    late CompanionServer server;
    late CompanionClient client;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('gopher-companion-');
      final paths = CompanionPaths(root.path, '${root.path}/control.sock');
      server = CompanionServer(paths);
      await server.start();
      client = CompanionClient(paths, '/missing-test-executable');
    });
    tearDown(() async {
      await server.close();
      await root.delete(recursive: true);
    });

    test(
      'imports are idempotent, persisted, and delivered through actual Gopher text framing',
      () async {
        final message = {'action': 'import', 'id': firstId, 'page': page()};
        final result = await client.request(message);
        await client.request(message);
        expect(
          (await client.request({'action': 'list'}))['pages'],
          hasLength(1),
        );
        final address = GopherAddress.fromUrl(result['url'] as String);
        final transport = GopherClient();
        final menu = await transport.fetchMenu(address);
        final article = menu.firstWhere(
          (item) => item.displayText == 'Read article',
        );
        expect(await transport.fetchText(article.address), page()['article']);
        expect(menu.first.displayText, 'A quiet café with a title ');
        await server.close();
        server = CompanionServer(client.paths);
        await server.start();
        expect(
          (await client.request({'action': 'list'}))['pages'],
          hasLength(1),
        );
        expect(await transport.fetchText(article.address), page()['article']);
      },
    );

    test(
      'menus resolve saved destinations locally while retaining external web and Gopher links',
      () async {
        await client.request({
          'action': 'import',
          'id': firstId,
          'page': page(
            links: [
              {
                'id': 1,
                'label': 'Another page',
                'url': 'https://example.org/second#section',
              },
              {
                'id': 2,
                'label': 'Remote Gopher',
                'url': 'gopher://example.org/0/readme',
              },
            ],
          ),
        });
        final address = GopherAddress.fromUrl(server.library.pageUrl(firstId));
        final transport = GopherClient();
        var menu = await transport.fetchMenu(address);
        expect(
          menu
              .firstWhere((item) => item.displayText.startsWith('[1]'))
              .selector,
          'URL:https://example.org/second#section',
        );
        await client.request({
          'action': 'import',
          'id': secondId,
          'page': page(url: 'https://example.org/second'),
        });
        menu = await transport.fetchMenu(address);
        expect(
          menu
              .firstWhere((item) => item.displayText.startsWith('[1]'))
              .selector,
          '/page/$secondId',
        );
        final remote = menu.firstWhere(
          (item) => item.displayText.startsWith('[2]'),
        );
        expect(remote.toUrl(), 'gopher://example.org:70/0/readme');
        await client.request({'action': 'remove', 'id': secondId});
        expect(
          (await client.request({'action': 'list'}))['pages'],
          hasLength(1),
        );
        expect(
          await File('${root.path}/pages/$secondId.json').exists(),
          isFalse,
        );
      },
    );

    test(
      'invalid IDs, URLs and protocol versions cannot alter the library',
      () async {
        for (final message in [
          {'action': 'import', 'id': '../escape', 'page': page()},
          {
            'action': 'import',
            'id': firstId,
            'page': page(url: 'file:///etc/passwd'),
          },
          {
            'action': 'import',
            'id': firstId,
            'page': page(
              links: [
                {'id': 1, 'label': 'Unsafe', 'url': 'javascript:alert(1)'},
              ],
            ),
          },
          {'protocolVersion': 999, 'action': 'status'},
        ]) {
          await expectLater(client.request(message), throwsFormatException);
        }
        expect(server.library.pages, isEmpty);
      },
    );

    test(
      'oversized input selectors cannot break subsequent Gopher requests',
      () async {
        final socket = await Socket.connect('127.0.0.1', companionPort);
        socket.write('${'x' * 5000}\r\n');
        await socket.flush();
        await socket.drain<void>();
        socket.destroy();
        expect(
          await GopherClient().fetchMenu(
            GopherAddress.fromUrl(server.library.rootUrl),
          ),
          isNotEmpty,
        );
      },
    );

    test(
      'damaged saved copies are preserved and explicitly removable',
      () async {
        await File('${root.path}/pages/$firstId.json').writeAsString('{broken');
        await server.library.load();
        expect(server.library.unreadable, [firstId]);
        await expectLater(
          client.request({'action': 'import', 'id': firstId, 'page': page()}),
          throwsFormatException,
        );
        expect(
          await File('${root.path}/pages/$firstId.json').readAsString(),
          '{broken',
        );
        await client.request({'action': 'remove', 'id': firstId});
        expect(server.library.unreadable, isEmpty);
      },
    );

    test(
      'stop removes automatic restart marker and closes both sockets without deleting saved pages',
      () async {
        await client.request({
          'action': 'import',
          'id': firstId,
          'page': page(),
        });
        expect((await client.request({'action': 'stop'}))['stopping'], isTrue);
        await server.done.future;
        expect(await File('${root.path}/enabled').exists(), isFalse);
        expect(await File('${root.path}/pages/$firstId.json').exists(), isTrue);
        await expectLater(
          client.request({'action': 'status'}),
          throwsA(isA<SocketException>()),
        );
      },
    );
  });

  test('document limits and duplicate link IDs are enforced', () {
    expect(
      () => checkedPage(page()..['article'] = 'x' * 600001),
      throwsFormatException,
    );
    expect(
      () => checkedPage(
        page(
          links: [
            {'id': 1, 'url': 'https://example.org/a', 'label': 'A'},
            {'id': 1, 'url': 'https://example.org/b', 'label': 'B'},
          ],
        ),
      ),
      throwsFormatException,
    );
  });
}
